// Worker job'larının PostgreSQL'e karşı uçtan uca testi. Dış API'ler (GeckoTerminal,
// DEXScreener, DefiLlama) `fetch` stub'ıyla taklit edilir.
// Çalıştırmak için: TEST_DATABASE_URL=postgresql://... npm test
// (Veritabanı `prisma migrate deploy` ile hazırlanmış olmalı; test tabloları temizler.)

import { PrismaPg } from '@prisma/adapter-pg';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { PrismaClient } from '@/generated/prisma/client';
import { MemoryCache, CACHE_KEYS } from '@/server/cache';
import type { Config } from '@/server/config';
import type { JobContext } from '@/server/jobs/context';
import { discoverTokens } from '@/server/jobs/discoverTokens';
import { finalizeHour } from '@/server/jobs/finalizeHour';
import { publishSnapshot } from '@/server/jobs/publishSnapshot';
import { refreshMarkets } from '@/server/jobs/refreshMarkets';
import { recordWalletActivity, recordWhaleTrades } from '@/server/ingest/swaps';
import type { DashboardSnapshot } from '@/lib/types';
import { buildSnapshot } from '@/lib/analytics/snapshot';
import { writeRawData } from '@/server/seed';
import { simulateRawData } from '@/server/simulation';
import { loadRawFromDb } from '@/server/snapshot/loadFromDb';

const url = process.env.TEST_DATABASE_URL;

const SOL_A = 'AaaaMeowGptMint1111111111111111111111pump';
const SOL_B = 'BbbbPlainMint22222222222222222222222222222';
const BSC_C = '0x00000000000000000000000000000000000c4444';

/** Adres → DEXScreener piyasası. Testler arasında değiştirilir. */
const market = new Map<string, { cap: number; liq: number; vol1h: number }>([
  [SOL_A, { cap: 150_000, liq: 20_000, vol1h: 40_000 }],
  [SOL_B, { cap: 60_000, liq: 9_000, vol1h: 5_000 }],
  [BSC_C, { cap: 90_000, liq: 120_000, vol1h: 30_000 }],
]);

/** true iken DEXScreener 404 döner (sağlayıcı kesintisi). */
let dexscreenerDown = false;

const geckoPools: Record<string, Array<{ address: string; name: string; symbol: string }>> = {
  solana: [
    { address: SOL_A, name: 'Meow GPT', symbol: 'MEOWGPT' },
    { address: SOL_B, name: 'Plain Coin', symbol: 'PLAIN' },
  ],
  bsc: [{ address: BSC_C, name: 'Safu Dog', symbol: 'SAFUDOG' }],
  robinhood: [],
};

function stubFetch(input: string | URL | Request): Promise<Response> {
  const u = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  const json = (body: unknown) => Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));

  if (u.hostname === 'api.geckoterminal.com') {
    const network = u.pathname.split('/')[4]!;
    const pools = u.searchParams.get('page') === '1' ? (geckoPools[network] ?? []) : [];
    return json({
      data: pools.map((p) => ({
        id: `${network}_pool_${p.address}`,
        attributes: { address: `pool_${p.address}`, name: `${p.symbol} / SOL`, pool_created_at: new Date(Date.UTC(2026, 8, 28, 9)).toISOString() },
        relationships: { base_token: { data: { id: `${network}_${p.address}` } }, dex: { data: { id: 'raydium' } } },
      })),
      included: pools.map((p) => ({ id: `${network}_${p.address}`, type: 'token', attributes: p })),
    });
  }
  if (u.hostname === 'api.dexscreener.com') {
    if (dexscreenerDown) return Promise.resolve(new Response('yok', { status: 404 }));
    const [, , , chainId, list] = u.pathname.split('/');
    const addresses = decodeURIComponent(list!).split(',');
    return json(
      addresses.flatMap((address) => {
        const m = market.get(address);
        if (!m) return [];
        return [
          {
            chainId,
            dexId: 'raydium',
            pairAddress: `pair_${address}`,
            baseToken: { address, name: address, symbol: 'X' },
            quoteToken: { address: 'quote', symbol: 'Q' },
            priceUsd: String(m.cap / 1e9),
            priceNative: '0.000001',
            txns: { h1: { buys: 30, sells: 20 }, h24: { buys: 300, sells: 200 } },
            volume: { h1: m.vol1h, h24: m.vol1h * 20 },
            priceChange: { h1: 5, h24: 50 },
            liquidity: { usd: m.liq },
            marketCap: m.cap,
            fdv: m.cap,
          },
        ];
      }),
    );
  }
  if (u.hostname === 'api.llama.fi') {
    if (u.pathname === '/v2/chains') return json([{ name: 'Solana', tvl: 1e10 }, { name: 'BSC', tvl: 7e9 }]);
    return json({ total24h: 2e9 });
  }
  return Promise.resolve(new Response('bilinmeyen host', { status: 404 }));
}

const config: Config = {
  DATA_MODE: 'live',
  DEXSCREENER_BASE_URL: 'https://api.dexscreener.com',
  GECKOTERMINAL_BASE_URL: 'https://api.geckoterminal.com/api/v2',
  DEFILLAMA_BASE_URL: 'https://api.llama.fi',
  ROBINHOOD_DEXSCREENER_ID: 'robinhood',
  ROBINHOOD_GECKO_NETWORK: 'robinhood',
  ROBINHOOD_DEFILLAMA_NAME: 'Robinhood',
  MILESTONE_USD: 100_000,
  WHALE_MIN_USD: 10_000,
  BOT_TX_PER_HOUR: 30,
};

describe.skipIf(!url)('worker hattı (PostgreSQL)', () => {
  let prisma: PrismaClient;
  const cache = new MemoryCache();
  let clock = new Date('2026-09-28T10:02:00Z');
  let ctx: JobContext;

  beforeAll(async () => {
    vi.stubGlobal('fetch', vi.fn(stubFetch));
    prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: url! }) });
    await prisma.$transaction([
      prisma.whaleTrade.deleteMany(),
      prisma.socialMetrics.deleteMany(),
      prisma.token.deleteMany(),
      prisma.volumeByHour.deleteMany(),
      prisma.chainStats.deleteMany(),
      prisma.launchDaily.deleteMany(),
      prisma.smartWallet.deleteMany(),
    ]);
    ctx = { prisma, cache, config, now: () => clock, log: { info: () => {}, warn: () => {}, error: () => {} } };
  });

  afterAll(async () => {
    vi.unstubAllGlobals();
    await prisma?.$disconnect();
  });

  it('discoverTokens yeni token’ları launchpad ve narrative etiketiyle ekler, tekrarları atlar', async () => {
    await discoverTokens(ctx);
    await discoverTokens(ctx);
    const tokens = await prisma.token.findMany({ orderBy: { symbol: 'asc' } });
    expect(tokens.map((t) => t.symbol)).toEqual(['MEOWGPT', 'PLAIN', 'SAFUDOG']);
    const meow = tokens.find((t) => t.symbol === 'MEOWGPT')!;
    expect(meow.launchpad).toBe('PUMP_FUN');
    expect(meow.narratives).toEqual(expect.arrayContaining(['ai', 'cat']));
    expect(tokens.find((t) => t.symbol === 'SAFUDOG')!.launchpad).toBe('FOUR_MEME');
  });

  it('100K eşiği iki ardışık örnekte onaylanır ve LaunchDaily’ye yansır', async () => {
    await refreshMarkets(ctx);
    let meow = await prisma.token.findUniqueOrThrow({ where: { chain_address: { chain: 'SOLANA', address: SOL_A } } });
    expect(meow.milestoneStreak).toBe(1);
    expect(meow.milestone100kAt).toBeNull();

    clock = new Date('2026-09-28T10:07:00Z');
    await refreshMarkets(ctx);
    meow = await prisma.token.findUniqueOrThrow({ where: { chain_address: { chain: 'SOLANA', address: SOL_A } } });
    expect(meow.milestone100kAt?.toISOString()).toBe('2026-09-28T10:02:00.000Z');

    // Likidite yolu: mcap 90K ama likidite 120K → sayılır.
    const safu = await prisma.token.findUniqueOrThrow({ where: { chain_address: { chain: 'BSC', address: BSC_C } } });
    expect(safu.milestone100kAt).not.toBeNull();
    // Eşik altı token sayılmaz.
    const plain = await prisma.token.findUniqueOrThrow({ where: { chain_address: { chain: 'SOLANA', address: SOL_B } } });
    expect(plain.milestone100kAt).toBeNull();

    const sol = await prisma.launchDaily.findUniqueOrThrow({
      where: { chain_day: { chain: 'SOLANA', day: new Date('2026-09-28T00:00:00Z') } },
    });
    expect(sol.crossed100k).toBe(1);
    expect(sol.byLaunchpad).toEqual({ PUMP_FUN: 1 });
    expect(sol.newTokens).toBe(2);
  });

  it('zincir saat satırlarını ve Activity Index’i yazar', async () => {
    const hourStart = new Date('2026-09-28T10:00:00Z');
    const vol = await prisma.volumeByHour.findUniqueOrThrow({ where: { chain_hourStart: { chain: 'SOLANA', hourStart } } });
    expect(vol.volumeUsd).toBe(45_000);
    expect(vol.txCount).toBe(100);
    const stats = await prisma.chainStats.findUniqueOrThrow({ where: { chain_hourStart: { chain: 'SOLANA', hourStart } } });
    expect(stats.tvlUsd).toBe(1e10);
    expect(stats.activeTokens).toBe(2);
    expect(stats.activityIndex).not.toBeNull();
  });

  it('sağlayıcı kesintisinde saat satırını sıfırlarla ezmez', async () => {
    const hourStart = new Date('2026-09-28T10:00:00Z');
    dexscreenerDown = true;
    clock = new Date('2026-09-28T10:12:00Z');
    try {
      await refreshMarkets(ctx);
    } finally {
      dexscreenerDown = false;
    }
    const vol = await prisma.volumeByHour.findUniqueOrThrow({ where: { chain_hourStart: { chain: 'SOLANA', hourStart } } });
    expect(vol.volumeUsd).toBe(45_000);
    const meow = await prisma.token.findUniqueOrThrow({ where: { chain_address: { chain: 'SOLANA', address: SOL_A } } });
    expect(meow.isActive).toBe(true);
  });

  it('saat kapanışında cüzdan sayaçlarından bot/insan ayrımı yapılır', async () => {
    const inHour = new Date('2026-09-28T10:30:00Z');
    await recordWalletActivity(cache, 'solana', [
      ...Array.from({ length: 40 }, () => ({ wallet: 'botWallet', at: inHour })),
      { wallet: 'human1', at: inHour },
      { wallet: 'human2', at: inHour },
    ]);
    clock = new Date('2026-09-28T11:01:30Z');
    await finalizeHour(ctx);
    const vol = await prisma.volumeByHour.findUniqueOrThrow({
      where: { chain_hourStart: { chain: 'SOLANA', hourStart: new Date('2026-09-28T10:00:00Z') } },
    });
    expect(vol).toMatchObject({ botTxCount: 40, humanTxCount: 2 });
    expect(await cache.getFields(CACHE_KEYS.walletCounter('solana', new Date('2026-09-28T10:00:00Z')))).toEqual({});
  });

  it('balina swapları idempotent yazılır ve smart money etiketlenir', async () => {
    await prisma.smartWallet.create({ data: { chain: 'SOLANA', address: 'whaleWallet', label: 'Fon' } });
    const swap = {
      chain: 'solana' as const,
      txHash: 'sigX',
      index: 0,
      wallet: 'whaleWallet',
      tokenAddress: SOL_A,
      tokenSymbol: 'MEOWGPT',
      side: 'BUY' as const,
      usdValue: 42_000,
      blockTime: new Date('2026-09-28T10:59:00Z'),
    };
    const deps = { prisma, cache, whaleMinUsd: 10_000 };
    expect(await recordWhaleTrades(deps, 'solana', [swap, { ...swap, txHash: 'small', usdValue: 500 }])).toBe(1);
    expect(await recordWhaleTrades(deps, 'solana', [swap])).toBe(0);
    const [trade] = await prisma.whaleTrade.findMany();
    expect(trade).toMatchObject({ id: 'solana:sigX:0', isSmartMoney: true, walletLabel: 'Fon' });
    expect(trade!.tokenId).not.toBeNull();
  });

  it('publishSnapshot veritabanından snapshot üretip önbelleğe yazar', async () => {
    await publishSnapshot(ctx);
    const snap = JSON.parse((await cache.get(CACHE_KEYS.snapshot))!) as DashboardSnapshot;
    expect(snap.mode).toBe('live');
    expect(snap.launches.days.find((d) => d.date === '2026-09-28')).toMatchObject({ solana: 1, bsc: 1, robinhood: 0 });
    expect(snap.whales.trades).toHaveLength(1);
    expect(snap.chains.map((c) => c.chain)).toEqual(['solana', 'bsc']);
  });
});

describe.skipIf(!url)('snapshot eşdeğerliği (PostgreSQL ↔ simülatör)', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: url! }) });
  });
  afterAll(async () => {
    await prisma?.$disconnect();
  });

  it('veritabanına yazılıp geri okunan ham veri aynı analitiği üretir', async () => {
    const now = new Date('2026-09-28T14:37:00Z');
    const raw = simulateRawData(now);
    await writeRawData(prisma, raw);
    const fromDb = buildSnapshot(await loadRawFromDb(prisma, now));
    const fromSim = buildSnapshot(raw);

    expect(fromDb.mode).toBe('live');
    expect(fromDb.chains).toEqual(fromSim.chains);
    expect(fromDb.launches).toEqual(fromSim.launches);
    expect(fromDb.trade).toEqual(fromSim.trade);
    expect(fromDb.whales).toEqual(fromSim.whales);
    expect(fromDb.coinOfTheDay?.address).toBe(fromSim.coinOfTheDay?.address);
  }, 30_000);
});
