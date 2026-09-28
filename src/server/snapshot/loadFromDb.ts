// PostgreSQL → RawDashboardData. Snapshot üreticisinin canlı moddaki girdisi.

import type { PrismaClient } from '@/generated/prisma/client';
import { chainFromPrisma } from '@/lib/chains';
import { DAY_MS, HOUR_MS, dayKey, floorToDay, floorToHour } from '@/lib/analytics/stats';
import type { Launchpad, RawDashboardData } from '@/lib/types';

const HOURS_WINDOW_MS = 35 * DAY_MS;
const STATS_WINDOW_MS = 8 * DAY_MS;
const TOKEN_LIMIT = 500;

export async function loadRawFromDb(prisma: PrismaClient, now: Date): Promise<RawDashboardData> {
  const currentHour = floorToHour(now).getTime();
  const today = floorToDay(now).getTime();

  const [hours, stats, launches, tokens, whales] = await Promise.all([
    prisma.volumeByHour.findMany({
      where: { hourStart: { gte: new Date(currentHour - HOURS_WINDOW_MS) } },
      orderBy: { hourStart: 'asc' },
    }),
    prisma.chainStats.findMany({
      where: { hourStart: { gte: new Date(currentHour - STATS_WINDOW_MS) } },
      orderBy: { hourStart: 'asc' },
    }),
    prisma.launchDaily.findMany({ where: { day: { gte: new Date(today - 30 * DAY_MS) } } }),
    prisma.token.findMany({
      where: { isActive: true, liquidityUsd: { gte: 5_000 } },
      orderBy: { volume24hUsd: { sort: 'desc', nulls: 'last' } },
      take: TOKEN_LIMIT,
    }),
    prisma.whaleTrade.findMany({
      where: { blockTime: { gte: new Date(now.getTime() - DAY_MS) } },
      orderBy: { blockTime: 'desc' },
      take: 300,
    }),
  ]);

  // Kaynaklar (X, Telegram, Farcaster, birleşik) token × saat bazında toplanır.
  const social = await prisma.socialMetrics.groupBy({
    by: ['tokenId', 'hourStart'],
    where: {
      tokenId: { in: tokens.map((t) => t.id) },
      hourStart: { gte: new Date(currentHour - 47 * HOUR_MS) },
    },
    _sum: { mentions: true, engagements: true, uniqueAuthors: true },
    _avg: { sentiment: true },
  });
  const tokenById = new Map(tokens.map((t) => [t.id, t]));

  return {
    now,
    mode: 'live',
    hours: hours.map((h) => ({
      chain: chainFromPrisma(h.chain),
      hourStart: h.hourStart,
      volumeUsd: h.volumeUsd,
      txCount: h.txCount,
      buyCount: h.buyCount,
      sellCount: h.sellCount,
      botTxCount: h.botTxCount,
      humanTxCount: h.humanTxCount,
      volatilityPct: h.volatilityPct,
      newPools: h.newPools,
    })),
    chainStats: stats.map((s) => ({
      chain: chainFromPrisma(s.chain),
      hourStart: s.hourStart,
      volume1hUsd: s.volume1hUsd,
      volume24hUsd: s.volume24hUsd,
      txCount1h: s.txCount1h,
      txCount24h: s.txCount24h,
      newPools1h: s.newPools1h,
      newPools24h: s.newPools24h,
      tvlUsd: s.tvlUsd,
    })),
    launches: launches.map((l) => ({
      chain: chainFromPrisma(l.chain),
      day: dayKey(l.day),
      crossed100k: l.crossed100k,
      newTokens: l.newTokens,
      byLaunchpad: (l.byLaunchpad ?? {}) as Partial<Record<Launchpad, number>>,
    })),
    tokens: tokens.map((t) => ({
      chain: chainFromPrisma(t.chain),
      address: t.address,
      symbol: t.symbol,
      name: t.name,
      launchpad: t.launchpad,
      narratives: t.narratives,
      poolCreatedAt: t.poolCreatedAt,
      priceUsd: t.priceUsd,
      priceChange1hPct: t.priceChange1hPct,
      priceChange24hPct: t.priceChange24hPct,
      marketCapUsd: t.marketCapUsd ?? t.fdvUsd,
      liquidityUsd: t.liquidityUsd,
      volume24hUsd: t.volume24hUsd,
      txCount24h: t.txCount24h,
      milestone100kAt: t.milestone100kAt,
    })),
    social: social.flatMap((s) => {
      const token = tokenById.get(s.tokenId);
      if (!token) return [];
      return [
        {
          chain: chainFromPrisma(token.chain),
          address: token.address,
          hourStart: s.hourStart,
          mentions: s._sum.mentions ?? 0,
          engagements: s._sum.engagements ?? 0,
          uniqueAuthors: s._sum.uniqueAuthors ?? 0,
          sentiment: s._avg.sentiment ?? null,
        },
      ];
    }),
    whales: whales.map((w) => ({
      id: w.id,
      chain: chainFromPrisma(w.chain),
      tokenAddress: w.tokenAddress,
      tokenSymbol: w.tokenSymbol,
      wallet: w.wallet,
      walletLabel: w.walletLabel,
      isSmartMoney: w.isSmartMoney,
      side: w.side,
      usdValue: w.usdValue,
      txHash: w.txHash,
      blockTime: w.blockTime,
    })),
  };
}
