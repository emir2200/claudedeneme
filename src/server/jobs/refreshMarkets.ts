// Job: piyasa yenilemesi + 100K tespiti + zincir metrikleri (her 5 dakikada bir).
//
// Zincir başına:
//  1. Takip evrenindeki aktif token'lar (hacme göre ilk 1500) 30'arlı gruplar halinde
//     DEXScreener'dan yenilenir.
//  2. Her token için 100K eşik durumu ilerletilir (advanceMilestone) ve Token'a yazılır.
//  3. Evrenin toplamları içinde bulunulan saatin VolumeByHour ve ChainStats satırlarına
//     yazılır (upsert: saat boyunca üzerine yazılır, saat kapanınca kesinleşir).
// Ardından tüm zincirler için Activity Index hesaplanır ve bugünün/dünün LaunchDaily
// sayaçları Token tablosundan yeniden sayılır (gece yarısına yakın onaylar kaçmasın diye).

import { CHAIN_IDS, chainToPrisma, type ChainId } from '@/lib/chains';
import { computeActivityIndex, type ChainMetricSample } from '@/lib/analytics/activityIndex';
import { detectLaunchpad } from '@/lib/analytics/launchpads';
import { advanceMilestone, DEFAULT_MILESTONE_CONFIG } from '@/lib/analytics/milestones';
import { DAY_MS, HOUR_MS, floorToDay, floorToHour } from '@/lib/analytics/stats';
import { CACHE_KEYS } from '../cache';
import { providerIds } from '../config';
import { fetchChainDexVolume24h, fetchChainTvls } from '../providers/defillama';
import { DEXSCREENER_BATCH, fetchTokenPairs, summarizeToken, type DexPair } from '../providers/dexscreener';
import { chunk, errorInfo, type JobContext } from './context';

const MAX_TRACKED_PER_CHAIN = 1500;
/** Bu orandan fazla grup alınamazsa toplamlar eksik olur; saat satırı yazılmaz. */
const MAX_FAILED_BATCH_RATIO = 0.2;
const MIN_ALIVE_LIQUIDITY_USD = 1_000;
const GRACE_PERIOD_MS = 24 * HOUR_MS;

interface ChainTotals {
  volume1hUsd: number;
  volume24hUsd: number;
  buys1h: number;
  sells1h: number;
  txCount24h: number;
  volatilityWeight: number;
  activeTokens: number;
  trackedTokens: number;
  batches: number;
  failedBatches: number;
}

export async function refreshMarkets(ctx: JobContext): Promise<void> {
  const now = ctx.now();
  const hourStart = floorToHour(now);
  const ids = providerIds(ctx.config);
  const llama = await getLlamaContext(ctx);

  for (const chain of CHAIN_IDS) {
    try {
      const totals = await refreshChainTokens(ctx, chain, ids[chain].dexscreener, now);
      if (totals.trackedTokens === 0) {
        // "Veri yok" ile "sıfır aktivite" karışmasın: evren boşsa saat satırı yazılmaz.
        ctx.log.warn(`refreshMarkets: ${chain} için takip edilen token yok, saat satırı yazılmadı`);
        continue;
      }
      if (totals.failedBatches > totals.batches * MAX_FAILED_BATCH_RATIO) {
        // Sağlayıcı kesintisi: eksik toplamlar "piyasa durdu" gibi görünmesin; önceki değer korunur.
        ctx.log.warn(`refreshMarkets: ${chain} için grupların çoğu alınamadı, saat satırı güncellenmedi`, {
          failed: totals.failedBatches,
          batches: totals.batches,
        });
        continue;
      }
      await writeChainHour(ctx, chain, totals, now, llama[chain]);
    } catch (err) {
      ctx.log.error(`refreshMarkets: ${chain} başarısız`, errorInfo(err));
    }
  }
  await updateActivityIndex(ctx, hourStart);
  await updateLaunchDaily(ctx, now);
}

async function refreshChainTokens(ctx: JobContext, chain: ChainId, dexId: string, now: Date): Promise<ChainTotals> {
  const tokens = await ctx.prisma.token.findMany({
    where: { chain: chainToPrisma(chain), isActive: true },
    orderBy: [{ volume24hUsd: { sort: 'desc', nulls: 'last' } }, { firstSeenAt: 'desc' }],
    take: MAX_TRACKED_PER_CHAIN,
    select: {
      id: true,
      address: true,
      launchpad: true,
      poolCreatedAt: true,
      firstSeenAt: true,
      peakMarketCapUsd: true,
      milestoneStreak: true,
      milestonePendingAt: true,
      milestone100kAt: true,
    },
  });

  const totals: ChainTotals = {
    volume1hUsd: 0,
    volume24hUsd: 0,
    buys1h: 0,
    sells1h: 0,
    txCount24h: 0,
    volatilityWeight: 0,
    activeTokens: 0,
    trackedTokens: tokens.length,
    batches: 0,
    failedBatches: 0,
  };

  for (const batch of chunk(tokens, DEXSCREENER_BATCH)) {
    totals.batches++;
    let pairs: DexPair[];
    try {
      pairs = await fetchTokenPairs(dexId, batch.map((t) => t.address));
    } catch (err) {
      totals.failedBatches++;
      ctx.log.warn(`refreshMarkets: ${chain} DEXScreener grubu atlandı`, errorInfo(err));
      continue;
    }

    const updates = batch.map((t) => {
      const m = summarizeToken(pairs, t.address);
      const bornAt = (t.poolCreatedAt ?? t.firstSeenAt).getTime();
      const pastGrace = now.getTime() - bornAt > GRACE_PERIOD_MS;
      if (!m) {
        // Havuzu hiç bulunamayan token grace süresinden sonra takipten çıkar.
        return ctx.prisma.token.update({ where: { id: t.id }, data: { isActive: !pastGrace, lastRefreshedAt: now } });
      }

      totals.volume1hUsd += m.volume1hUsd;
      totals.volume24hUsd += m.volume24hUsd;
      totals.buys1h += m.buys1h;
      totals.sells1h += m.sells1h;
      totals.txCount24h += m.txCount24h;
      totals.volatilityWeight += Math.abs(m.priceChange1hPct ?? 0) * m.volume1hUsd;
      totals.activeTokens++;

      const milestone = advanceMilestone(
        { streak: t.milestoneStreak, pendingSince: t.milestonePendingAt, crossedAt: t.milestone100kAt },
        { at: now, marketCapUsd: m.marketCapUsd, fdvUsd: m.fdvUsd, liquidityUsd: m.liquidityUsd },
        { ...DEFAULT_MILESTONE_CONFIG, thresholdUsd: ctx.config.MILESTONE_USD },
      );
      const cap = m.marketCapUsd ?? m.fdvUsd;

      return ctx.prisma.token.update({
        where: { id: t.id },
        data: {
          pairAddress: m.pairAddress,
          dexId: m.dexId,
          quoteAddress: m.quoteAddress,
          launchpad: t.launchpad === 'OTHER' ? detectLaunchpad(chain, t.address, m.dexId) : t.launchpad,
          poolCreatedAt: t.poolCreatedAt ?? m.pairCreatedAt,
          priceUsd: m.priceUsd,
          priceNative: m.priceNative,
          priceChange1hPct: m.priceChange1hPct,
          priceChange24hPct: m.priceChange24hPct,
          marketCapUsd: m.marketCapUsd,
          fdvUsd: m.fdvUsd,
          liquidityUsd: m.liquidityUsd,
          volume1hUsd: m.volume1hUsd,
          volume24hUsd: m.volume24hUsd,
          txCount1h: m.buys1h + m.sells1h,
          txCount24h: m.txCount24h,
          peakMarketCapUsd: cap === null ? t.peakMarketCapUsd : Math.max(cap, t.peakMarketCapUsd ?? 0),
          milestoneStreak: milestone.streak,
          milestonePendingAt: milestone.pendingSince,
          milestone100kAt: milestone.crossedAt,
          isActive: !(pastGrace && m.liquidityUsd < MIN_ALIVE_LIQUIDITY_USD),
          lastRefreshedAt: now,
        },
      });
    });
    await ctx.prisma.$transaction(updates);
  }
  return totals;
}

async function writeChainHour(
  ctx: JobContext,
  chain: ChainId,
  totals: ChainTotals,
  now: Date,
  context: { tvlUsd: number | null; dexVolume24hUsd: number | null },
) {
  const hourStart = floorToHour(now);
  const prismaChain = chainToPrisma(chain);
  const countSince = (since: Date) =>
    ctx.prisma.token.count({ where: { chain: prismaChain, poolCreatedAt: { gte: since } } });
  const [newPools1h, newPools24h, newPoolsThisHour] = await Promise.all([
    countSince(new Date(now.getTime() - HOUR_MS)),
    countSince(new Date(now.getTime() - DAY_MS)),
    countSince(hourStart),
  ]);

  const txCount1h = totals.buys1h + totals.sells1h;
  const volatilityPct = totals.volume1hUsd > 0 ? totals.volatilityWeight / totals.volume1hUsd : 0;
  const hourData = {
    volumeUsd: totals.volume1hUsd,
    txCount: txCount1h,
    buyCount: totals.buys1h,
    sellCount: totals.sells1h,
    volatilityPct,
    newPools: newPoolsThisHour,
  };
  // botTxCount / humanTxCount burada yazılmaz; saat kapanışında finalizeHour doldurur.
  await ctx.prisma.volumeByHour.upsert({
    where: { chain_hourStart: { chain: prismaChain, hourStart } },
    create: { chain: prismaChain, hourStart, ...hourData },
    update: hourData,
  });

  const statsData = {
    capturedAt: now,
    volume1hUsd: totals.volume1hUsd,
    volume24hUsd: totals.volume24hUsd,
    txCount1h,
    txCount24h: totals.txCount24h,
    newPools1h,
    newPools24h,
    tvlUsd: context.tvlUsd,
    dexVolume24hUsd: context.dexVolume24hUsd,
    activeTokens: totals.activeTokens,
  };
  await ctx.prisma.chainStats.upsert({
    where: { chain_hourStart: { chain: prismaChain, hourStart } },
    create: { chain: prismaChain, hourStart, ...statsData },
    update: statsData,
  });
}

async function updateActivityIndex(ctx: JobContext, hourStart: Date) {
  const rows = await ctx.prisma.chainStats.findMany({
    where: { hourStart: { gte: new Date(hourStart.getTime() - 168 * HOUR_MS), lte: hourStart } },
    orderBy: { hourStart: 'asc' },
  });
  const toSample = (r: (typeof rows)[number]): ChainMetricSample => ({
    volume24hUsd: r.volume24hUsd,
    volume1hUsd: r.volume1hUsd,
    txCount1h: r.txCount1h,
    newPools1h: r.newPools1h,
    tvlUsd: r.tvlUsd,
  });

  const inputs = CHAIN_IDS.flatMap((chain) => {
    const own = rows.filter((r) => r.chain === chainToPrisma(chain));
    const current = own.find((r) => r.hourStart.getTime() === hourStart.getTime());
    if (!current) return [];
    return [{ chain, current: toSample(current), history: own.filter((r) => r !== current).map(toSample) }];
  });

  await ctx.prisma.$transaction(
    computeActivityIndex(inputs).map((r) =>
      ctx.prisma.chainStats.update({
        where: { chain_hourStart: { chain: chainToPrisma(r.chain), hourStart } },
        data: { activityIndex: r.index },
      }),
    ),
  );
}

async function updateLaunchDaily(ctx: JobContext, now: Date) {
  const today = floorToDay(now).getTime();
  for (const dayStart of [today - DAY_MS, today]) {
    const from = new Date(dayStart);
    const to = new Date(dayStart + DAY_MS);
    for (const chain of CHAIN_IDS) {
      const prismaChain = chainToPrisma(chain);
      const [grouped, newTokens] = await Promise.all([
        ctx.prisma.token.groupBy({
          by: ['launchpad'],
          where: { chain: prismaChain, milestone100kAt: { gte: from, lt: to } },
          _count: { _all: true },
        }),
        ctx.prisma.token.count({ where: { chain: prismaChain, poolCreatedAt: { gte: from, lt: to } } }),
      ]);
      const byLaunchpad = Object.fromEntries(grouped.map((g) => [g.launchpad, g._count._all]));
      const crossed100k = grouped.reduce((a, g) => a + g._count._all, 0);
      await ctx.prisma.launchDaily.upsert({
        where: { chain_day: { chain: prismaChain, day: from } },
        create: { chain: prismaChain, day: from, crossed100k, newTokens, byLaunchpad },
        update: { crossed100k, newTokens, byLaunchpad },
      });
    }
  }
}

type LlamaContext = Record<ChainId, { tvlUsd: number | null; dexVolume24hUsd: number | null }>;

/** DefiLlama bağlam metrikleri yavaş değişir; 10 dakika önbelleklenir. */
async function getLlamaContext(ctx: JobContext): Promise<LlamaContext> {
  const cached = await ctx.cache.get(CACHE_KEYS.llamaContext);
  if (cached) return JSON.parse(cached) as LlamaContext;

  const ids = providerIds(ctx.config);
  const tvls = await fetchChainTvls().catch((err) => {
    ctx.log.warn('DefiLlama TVL alınamadı', errorInfo(err));
    return new Map<string, number>();
  });
  const out = {} as LlamaContext;
  for (const chain of CHAIN_IDS) {
    const name = ids[chain].defillama;
    out[chain] = {
      tvlUsd: tvls.get(name.toLowerCase()) ?? null,
      dexVolume24hUsd: await fetchChainDexVolume24h(name).catch(() => null),
    };
  }
  await ctx.cache.set(CACHE_KEYS.llamaContext, JSON.stringify(out), 600);
  return out;
}
