// Deterministik piyasa simülatörü (demo modu ve veritabanı seed'i için).
//
// Amaç: API anahtarı olmadan panelin GERÇEK analitik hattını çalıştırmak. Üretilen
// değerler gerçekçi büyüklüklerde ama tamamen kurgusaldır; token adları uydurmadır.
// Aynı saat için aynı geçmiş üretilir (sayfa yenilendiğinde tarih "zıplamaz"),
// içinde bulunulan saat ve token metrikleri 5 dakikalık dilimlerle hafifçe oynar.
//
// Senaryo: Solana hacim liderliğini koruyor, BNB Chain son iki haftada ivmeleniyor,
// Robinhood Chain küçük ama ABD borsa saatlerine bağlı hızla büyüyen bir ekosistem.

import { CHAIN_IDS, type ChainId } from '@/lib/chains';
import { detectLaunchpad } from '@/lib/analytics/launchpads';
import { classifyNarratives, NARRATIVES } from '@/lib/analytics/narratives';
import { DAY_MS, HOUR_MS, clamp, dayKey, floorToDay, floorToHour } from '@/lib/analytics/stats';
import type {
  Launchpad,
  RawChainStat,
  RawDashboardData,
  RawHour,
  RawLaunchDay,
  RawSocialHour,
  RawToken,
  RawWhale,
} from '@/lib/types';

// ─── Tohumlanmış rastgelelik ────────────────────────────────────────────────

function hashString(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

export type Rng = () => number;

export function rngFor(...parts: Array<string | number>): Rng {
  let a = hashString(parts.join('|'));
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function gaussian(rng: Rng): number {
  const u = Math.max(rng(), 1e-12);
  const v = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

const lognormal = (rng: Rng, sigma: number) => Math.exp(sigma * gaussian(rng));
const pick = <T>(rng: Rng, xs: readonly T[]): T => xs[Math.floor(rng() * xs.length)]!;

function weightedPick<T extends string>(rng: Rng, weights: Partial<Record<T, number>>): T {
  const entries = Object.entries(weights) as [T, number][];
  const total = entries.reduce((a, [, w]) => a + w, 0);
  let r = rng() * total;
  for (const [key, w] of entries) {
    r -= w;
    if (r <= 0) return key;
  }
  return entries[entries.length - 1]![0];
}

// ─── Zincir profilleri ──────────────────────────────────────────────────────

interface ChainProfile {
  baseVolumeHourly: number;
  peakHourUtc: number;
  secondaryPeakUtc: number;
  peakWidth: number;
  weekendFactor: number;
  /** Günlük üstel eğilim (0.02 → günde ~%2 büyüme). */
  trendPerDay: number;
  avgTradeUsd: number;
  botShare: number;
  newPoolsHourly: number;
  tvlUsd: number;
  launchesPerDay: number;
  launchpadMix: Partial<Record<Launchpad, number>>;
  tokenWeight: number;
  whaleWeight: number;
}

const PROFILES: Record<ChainId, ChainProfile> = {
  solana: {
    baseVolumeHourly: 85e6,
    peakHourUtc: 16,
    secondaryPeakUtc: 2,
    peakWidth: 4.5,
    weekendFactor: 0.86,
    trendPerDay: -0.004,
    avgTradeUsd: 320,
    botShare: 0.6,
    newPoolsHourly: 950,
    tvlUsd: 10.4e9,
    launchesPerDay: 170,
    launchpadMix: { PUMP_FUN: 0.78, OTHER: 0.22 },
    tokenWeight: 0.5,
    whaleWeight: 0.5,
  },
  bsc: {
    baseVolumeHourly: 52e6,
    peakHourUtc: 5,
    secondaryPeakUtc: 14,
    peakWidth: 4,
    weekendFactor: 0.95,
    trendPerDay: 0.022,
    avgTradeUsd: 540,
    botShare: 0.5,
    newPoolsHourly: 260,
    tvlUsd: 7.1e9,
    launchesPerDay: 95,
    launchpadMix: { FOUR_MEME: 0.84, OTHER: 0.16 },
    tokenWeight: 0.35,
    whaleWeight: 0.38,
  },
  robinhood: {
    baseVolumeHourly: 3.4e6,
    peakHourUtc: 17,
    secondaryPeakUtc: 14,
    peakWidth: 3.2,
    weekendFactor: 0.55,
    trendPerDay: 0.03,
    avgTradeUsd: 760,
    botShare: 0.33,
    newPoolsHourly: 22,
    tvlUsd: 1.8e8,
    launchesPerDay: 9,
    launchpadMix: { OTHER: 1 },
    tokenWeight: 0.15,
    whaleWeight: 0.12,
  },
};

function bump(hour: number, center: number, width: number): number {
  const d = Math.min(Math.abs(hour - center), 24 - Math.abs(hour - center));
  return Math.exp(-(d * d) / (2 * width * width));
}

/** 0–1 arası gün içi aktivite eğrisi. */
function diurnal(p: ChainProfile, hour: number): number {
  return clamp(0.75 * bump(hour, p.peakHourUtc, p.peakWidth) + 0.35 * bump(hour, p.secondaryPeakUtc, p.peakWidth));
}

function hourRow(chain: ChainId, hourStart: Date, now: Date): RawHour {
  const p = PROFILES[chain];
  const t = hourStart.getTime();
  const hourIndex = Math.floor(t / HOUR_MS);
  const rng = rngFor('hour', chain, hourIndex);
  // Eğilim saat başına sabitlenir: aynı saat içindeki tüm çağrılar birebir aynı geçmişi üretir.
  const daysAgo = (floorToHour(now).getTime() - t) / DAY_MS;
  const dow = (hourStart.getUTCDay() + 6) % 7;
  const d = diurnal(p, hourStart.getUTCHours());

  const trend = Math.exp(-p.trendPerDay * daysAgo);
  const weekend = dow >= 5 ? p.weekendFactor : 1;
  const spike = rng() < 0.03 ? 2.2 : 1;
  let volumeUsd = p.baseVolumeHourly * (0.35 + 1.1 * d) * trend * weekend * spike * lognormal(rng, 0.16);

  // İçinde bulunulan saat: son 60 dakikanın kayan değeri, 5 dakikalık dilimlerle oynar.
  if (t === floorToHour(now).getTime()) {
    volumeUsd *= 0.92 + 0.16 * rngFor('live', chain, Math.floor(now.getTime() / 300_000))();
  }

  const txCount = Math.round(volumeUsd / (p.avgTradeUsd * lognormal(rng, 0.1)));
  const buyCount = Math.round(txCount * clamp(0.5 + 0.06 * gaussian(rng), 0.3, 0.7));
  const botShare = clamp(p.botShare + 0.14 * (0.5 - d) + 0.04 * gaussian(rng), 0.1, 0.9);
  const botTxCount = Math.round(txCount * botShare);

  return {
    chain,
    hourStart,
    volumeUsd,
    txCount,
    buyCount,
    sellCount: txCount - buyCount,
    botTxCount,
    humanTxCount: txCount - botTxCount,
    volatilityPct: (2.5 + 7 * d) * lognormal(rng, 0.25) * (spike > 1 ? 1.8 : 1),
    newPools: Math.round(p.newPoolsHourly * (0.55 + 0.7 * d) * trend * lognormal(rng, 0.15)),
  };
}

function tvlAt(chain: ChainId, hourStart: Date): number {
  const p = PROFILES[chain];
  const day = Math.floor(hourStart.getTime() / DAY_MS);
  const drift = 1 + 0.03 * Math.sin(day / 4 + chain.length) + 0.01 * gaussian(rngFor('tvl', chain, day));
  return p.tvlUsd * drift;
}

// ─── Token evreni ───────────────────────────────────────────────────────────

const WORDS: Record<string, string[]> = {
  ai: ['NEURAL', 'GPT', 'AGENT', 'SYNTH', 'CYBER', 'BRAIN', 'AGI', 'ROBOT'],
  cat: ['MEOW', 'KITTY', 'NEKO', 'PURR', 'CATZ', 'KITTEN'],
  dog: ['WOOF', 'PUPPY', 'SHIBA', 'HOUND', 'DOGE'],
  frog: ['PEPE', 'FROG', 'TOAD', 'KEK', 'RIBBIT'],
  meta: ['WAGMI', 'CTO', 'BASED', 'DEGEN', 'SEND', 'JEET', 'TICKER'],
  political: ['MAGA', 'POTUS', 'VOTE', 'SENATE'],
  cz: ['SAFU', 'BINANCE', 'GIGGLE', 'FOUR'],
  stocks: ['STONK', 'HOOD', 'ROBIN', 'WSB', 'BULL'],
};
const SUFFIXES = ['LORD', 'KING', 'MAX', 'ZILLA', 'VERSE', 'PAD', 'WIFHAT', 'ONCHAIN', 'SZN', 'LAND'];

const NARRATIVE_CHAIN_BIAS: Record<ChainId, Record<string, number>> = {
  solana: { ai: 3, cat: 3, dog: 2, frog: 2, meta: 2, political: 2, cz: 0.2, stocks: 0.5 },
  bsc: { ai: 2, cat: 1.5, dog: 2, frog: 1, meta: 1, political: 0.5, cz: 4, stocks: 0.3 },
  robinhood: { ai: 1, cat: 1, dog: 1, frog: 0.5, meta: 1, political: 0.5, cz: 0.1, stocks: 5 },
};

const B58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
const HEX = '0123456789abcdef';
const randomString = (rng: Rng, alphabet: string, n: number) =>
  Array.from({ length: n }, () => alphabet[Math.floor(rng() * alphabet.length)]).join('');

function tokenAddress(rng: Rng, chain: ChainId, launchpad: Launchpad): string {
  if (chain === 'solana') return randomString(rng, B58, launchpad === 'PUMP_FUN' ? 40 : 44) + (launchpad === 'PUMP_FUN' ? 'pump' : '');
  if (chain === 'bsc') return '0x' + randomString(rng, HEX, launchpad === 'FOUR_MEME' ? 36 : 40) + (launchpad === 'FOUR_MEME' ? '4444' : '');
  return '0x' + randomString(rng, HEX, 40);
}

const titleCase = (w: string) => w.charAt(0) + w.slice(1).toLowerCase();

interface SimToken extends RawToken {
  hypeFactor: number;
}

const TOKENS_PER_DAY = 160;

function simulateTokens(now: Date): SimToken[] {
  const day = Math.floor(now.getTime() / DAY_MS);
  const slot = Math.floor(now.getTime() / 300_000);
  const rng = rngFor('tokens', day);
  const hot = hotNarrative(day);
  const starIndex = Math.floor(rngFor('star', day)() * 40);
  const seen = new Set<string>();
  const tokens: SimToken[] = [];

  while (tokens.length < TOKENS_PER_DAY) {
    const chain = weightedPick(rng, Object.fromEntries(CHAIN_IDS.map((c) => [c, PROFILES[c].tokenWeight])) as Record<ChainId, number>);
    const narrative = weightedPick(rng, NARRATIVE_CHAIN_BIAS[chain]);
    const first = pick(rng, WORDS[narrative]!);
    const secondPool = rng() < 0.45 ? WORDS[pick(rng, Object.keys(WORDS))]! : SUFFIXES;
    const second = pick(rng, secondPool);
    if (first === second) continue;
    const symbol = (first + second).slice(0, 12);
    if (seen.has(symbol)) continue;
    seen.add(symbol);

    const launchpad = weightedPick(rng, PROFILES[chain].launchpadMix);
    const address = tokenAddress(rng, chain, launchpad);
    const name = `${titleCase(first)} ${titleCase(second)}`;
    const narratives = classifyNarratives(name, symbol);

    const i = tokens.length;
    const isStar = i === starIndex;
    const marketCapUsd = Math.max(40_000, (isStar ? 9e6 : 7e5) * lognormal(rng, 1.25));
    const liquidityUsd = marketCapUsd * (0.04 + 0.18 * rng());
    const washy = rng() < 0.04;
    const volume24hUsd = marketCapUsd * (washy ? 7 + 5 * rng() : 0.9 * lognormal(rng, 0.8));
    const ageHours = Math.min(24 * 7, 1 + 38 * -Math.log(Math.max(rng(), 1e-6)));
    const poolCreatedAt = new Date(now.getTime() - ageHours * HOUR_MS);
    const narrativeBoost = narratives.includes(hot) ? 45 : 0;
    const jitter = rngFor('tok-live', day, i, slot);
    const priceChange24hPct = clamp(
      8 + narrativeBoost + (isStar ? 140 : 0) + 42 * gaussian(rng) + 6 * gaussian(jitter),
      -88,
      900,
    );
    const cap = marketCapUsd * (1 + 0.02 * gaussian(jitter));
    const crossedAt =
      cap >= 100_000
        ? new Date(Math.min(now.getTime(), poolCreatedAt.getTime() + (0.2 + 10 * rng()) * HOUR_MS))
        : null;

    tokens.push({
      chain,
      address,
      symbol,
      name,
      launchpad: detectLaunchpad(chain, address),
      narratives,
      poolCreatedAt,
      priceUsd: cap / 1e9,
      priceChange1hPct: priceChange24hPct / 8 + 3 * gaussian(jitter),
      priceChange24hPct,
      marketCapUsd: cap,
      liquidityUsd,
      volume24hUsd,
      txCount24h: Math.round(volume24hUsd / PROFILES[chain].avgTradeUsd),
      milestone100kAt: crossedAt,
      hypeFactor: isStar ? 7 : 0.6 + 0.8 * rng(),
    });
  }
  return tokens;
}

function hotNarrative(day: number): string {
  return NARRATIVES[Math.floor(rngFor('hot', day)() * NARRATIVES.length)]!.slug;
}

function narrativeGrowth(slug: string, day: number): number {
  if (slug === hotNarrative(day)) return 2.1;
  return 0.6 + 0.8 * rngFor('ngrowth', slug, day)();
}

function simulateSocial(tokens: readonly SimToken[], now: Date): RawSocialHour[] {
  const day = Math.floor(now.getTime() / DAY_MS);
  const currentHour = floorToHour(now).getTime();
  const out: RawSocialHour[] = [];
  for (const t of tokens) {
    const base = (2 + (t.marketCapUsd ?? 0) / 90_000) * t.hypeFactor;
    const growth = Math.max(...t.narratives.map((n) => narrativeGrowth(n, day)), 1);
    for (let k = 47; k >= 0; k--) {
      const hourStart = new Date(currentHour - k * HOUR_MS);
      if (t.poolCreatedAt && hourStart < floorToHour(t.poolCreatedAt)) continue;
      const rng = rngFor('social', t.address, hourStart.getTime());
      const recency = k < 24 ? 1 + (growth - 1) * ((24 - k) / 24) * 1.6 : 1;
      const d = diurnal(PROFILES[t.chain], hourStart.getUTCHours());
      const mentions = Math.round(base * (0.5 + d) * recency * lognormal(rng, 0.3));
      out.push({
        chain: t.chain,
        address: t.address,
        hourStart,
        mentions,
        engagements: Math.round(mentions * (6 + 24 * rng())),
        uniqueAuthors: Math.round(mentions * (0.4 + 0.3 * rng())),
        sentiment: clamp(0.45 + 0.3 * rng() + ((t.priceChange24hPct ?? 0) > 0 ? 0.1 : -0.08)),
      });
    }
  }
  return out;
}

// ─── Balina swapları ────────────────────────────────────────────────────────

const SMART_LABELS = ['Smart Money · Erken Alıcı', 'Smart Money · Fon', 'Smart Money · KOL', 'Smart Money · Sniper'];

function walletPool(chain: ChainId, day: number) {
  const rng = rngFor('wallets', chain, day);
  return Array.from({ length: 36 }, (_, i) => ({
    address: chain === 'solana' ? randomString(rng, B58, 44) : '0x' + randomString(rng, HEX, 40),
    label: i < 7 ? SMART_LABELS[i % SMART_LABELS.length]! : null,
  }));
}

function simulateWhales(tokens: readonly SimToken[], now: Date): RawWhale[] {
  const day = Math.floor(now.getTime() / DAY_MS);
  const minuteNow = Math.floor(now.getTime() / 60_000);
  const hot = hotNarrative(day);
  const byChain = Object.fromEntries(
    CHAIN_IDS.map((c) => [
      c,
      tokens
        .filter((t) => t.chain === c && (t.liquidityUsd ?? 0) > 60_000)
        .sort((a, b) => (b.volume24hUsd ?? 0) - (a.volume24hUsd ?? 0))
        .slice(0, 15),
    ]),
  ) as Record<ChainId, SimToken[]>;
  const wallets = Object.fromEntries(CHAIN_IDS.map((c) => [c, walletPool(c, day)])) as Record<
    ChainId,
    ReturnType<typeof walletPool>
  >;

  const out: RawWhale[] = [];
  for (let m = minuteNow - 6 * 60; m <= minuteNow; m++) {
    const rng = rngFor('whale', m);
    if (rng() > 0.14) continue;
    const chain = weightedPick(rng, Object.fromEntries(CHAIN_IDS.map((c) => [c, PROFILES[c].whaleWeight])) as Record<ChainId, number>);
    const pool = byChain[chain];
    if (pool.length === 0) continue;
    const token = pool[Math.min(pool.length - 1, Math.floor(pool.length * rng() * rng()))]!;
    const wallet = pick(rng, wallets[chain]);
    const blockTime = new Date(m * 60_000 + Math.floor(rng() * 60_000));
    if (blockTime > now) continue;
    const buyBias = token.narratives.includes(hot) ? 0.68 : 0.52;
    const txHash = chain === 'solana' ? randomString(rng, B58, 88) : '0x' + randomString(rng, HEX, 64);
    out.push({
      id: `${chain}:${txHash}:0`,
      chain,
      tokenAddress: token.address,
      tokenSymbol: token.symbol,
      wallet: wallet.address,
      walletLabel: wallet.label,
      isSmartMoney: wallet.label !== null,
      side: rng() < buyBias ? 'BUY' : 'SELL',
      usdValue: Math.min(750_000, 10_000 * lognormal(rng, 0.85) + 2_000),
      txHash,
      blockTime,
    });
  }
  return out.filter((w) => w.usdValue >= 10_000);
}

// ─── Günlük 100K çıkışları ──────────────────────────────────────────────────

function simulateLaunches(now: Date): RawLaunchDay[] {
  const today = floorToDay(now).getTime();
  const progress = (now.getTime() - today) / DAY_MS;
  const out: RawLaunchDay[] = [];
  for (const chain of CHAIN_IDS) {
    const p = PROFILES[chain];
    for (let k = 29; k >= 0; k--) {
      const dayStart = today - k * DAY_MS;
      const rng = rngFor('launch', chain, dayStart);
      const dow = (new Date(dayStart).getUTCDay() + 6) % 7;
      const expected =
        p.launchesPerDay * Math.exp(-p.trendPerDay * k) * (dow >= 5 ? p.weekendFactor : 1) * lognormal(rng, 0.14);
      const crossed = Math.round(expected * (k === 0 ? progress : 1));
      const byLaunchpad: Partial<Record<Launchpad, number>> = {};
      let remaining = crossed;
      const mix = Object.entries(p.launchpadMix) as [Launchpad, number][];
      mix.forEach(([lp, share], idx) => {
        const n = idx === mix.length - 1 ? remaining : Math.round(crossed * share);
        byLaunchpad[lp] = n;
        remaining -= n;
      });
      out.push({
        chain,
        day: dayKey(new Date(dayStart)),
        crossed100k: crossed,
        newTokens: Math.round(p.newPoolsHourly * 24 * Math.exp(-p.trendPerDay * k) * (k === 0 ? progress : 1)),
        byLaunchpad,
      });
    }
  }
  return out;
}

// ─── Ana giriş ──────────────────────────────────────────────────────────────

export const SIM_HOURS_BACK = 35 * 24;
export const SIM_STATS_HOURS_BACK = 8 * 24;

export function simulateRawData(now: Date = new Date()): RawDashboardData {
  const currentHour = floorToHour(now).getTime();
  const hours: RawHour[] = [];
  for (const chain of CHAIN_IDS) {
    for (let k = SIM_HOURS_BACK; k >= 0; k--) hours.push(hourRow(chain, new Date(currentHour - k * HOUR_MS), now));
  }

  const chainStats: RawChainStat[] = [];
  for (const chain of CHAIN_IDS) {
    const rows = hours.filter((h) => h.chain === chain);
    for (let i = rows.length - 1 - SIM_STATS_HOURS_BACK; i < rows.length; i++) {
      const window = rows.slice(Math.max(0, i - 23), i + 1);
      const row = rows[i]!;
      chainStats.push({
        chain,
        hourStart: row.hourStart,
        volume1hUsd: row.volumeUsd,
        volume24hUsd: window.reduce((a, h) => a + h.volumeUsd, 0),
        txCount1h: row.txCount,
        txCount24h: window.reduce((a, h) => a + h.txCount, 0),
        newPools1h: row.newPools,
        newPools24h: window.reduce((a, h) => a + h.newPools, 0),
        tvlUsd: tvlAt(chain, row.hourStart),
      });
    }
  }

  const simTokens = simulateTokens(now);
  const social = simulateSocial(simTokens, now);
  const whales = simulateWhales(simTokens, now);
  const tokens: RawToken[] = simTokens.map(({ hypeFactor, ...t }) => t);

  return {
    now,
    mode: 'demo',
    hours,
    chainStats,
    launches: simulateLaunches(now),
    tokens,
    social,
    whales,
  };
}

/** Seed için demo smart money cüzdanları. */
export function simulatedSmartWallets(now: Date = new Date()) {
  const day = Math.floor(now.getTime() / DAY_MS);
  return CHAIN_IDS.flatMap((chain) =>
    walletPool(chain, day)
      .filter((w) => w.label)
      .map((w) => ({ chain, address: w.address, label: w.label! })),
  );
}
