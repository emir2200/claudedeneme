// Ham veri → DashboardSnapshot. Saf fonksiyon: aynı girdi her zaman aynı çıktıyı verir.
// Canlı mod (PostgreSQL) ve demo mod (simülatör) aynı fonksiyondan geçer.

import { CHAIN_IDS, type ChainId } from '../chains';
import type {
  ChainActivity,
  DashboardSnapshot,
  LaunchDayPoint,
  LaunchReport,
  Launchpad,
  MatrixKey,
  RawChainStat,
  RawDashboardData,
  RawHour,
  TickerItem,
  TradeWindowReport,
  WhaleReport,
} from '../types';
import { computeActivityIndex, type ChainMetricSample } from './activityIndex';
import { DEFAULT_HYPE_FILTERS, scoreHype, type HypeCandidate } from './hype';
import { computeNarrativeTrends } from './narratives';
import { DAY_MS, HOUR_MS, dayKey, floorToDay, floorToHour, mean } from './stats';
import {
  MATRIX_WEEKS,
  bestWindow,
  buildHeatMatrix,
  currentStatus,
  hottestRecentHour,
  mergeBuckets,
} from './tradeWindows';
import { netFlow } from './whales';

export interface SnapshotOptions {
  milestoneUsd: number;
  whaleMinUsd: number;
}

export const DEFAULT_SNAPSHOT_OPTIONS: SnapshotOptions = { milestoneUsd: 100_000, whaleMinUsd: 10_000 };

const HISTORY_HOURS = 168;
const SPARKLINE_HOURS = 24;

function groupByChain<T extends { chain: ChainId }>(rows: readonly T[]): Record<ChainId, T[]> {
  const out = { solana: [], bsc: [], robinhood: [] } as Record<ChainId, T[]>;
  for (const r of rows) out[r.chain].push(r);
  return out;
}

function toSample(row: RawChainStat): ChainMetricSample {
  return {
    volume24hUsd: row.volume24hUsd,
    volume1hUsd: row.volume1hUsd,
    txCount1h: row.txCount1h,
    newPools1h: row.newPools1h,
    tvlUsd: row.tvlUsd,
  };
}

/** `t` anındaki (veya öncesindeki en son) satır. `rows` zamana göre artan sıralı olmalı. */
function rowAt(rows: readonly RawChainStat[], t: number): RawChainStat | null {
  let found: RawChainStat | null = null;
  for (const r of rows) {
    if (r.hourStart.getTime() <= t) found = r;
    else break;
  }
  return found;
}

function buildChains(raw: RawDashboardData): ChainActivity[] {
  const byChain = groupByChain(raw.chainStats);
  for (const id of CHAIN_IDS) byChain[id].sort((a, b) => a.hourStart.getTime() - b.hourStart.getTime());
  const currentHour = floorToHour(raw.now).getTime();

  const indexAt = (t: number) => {
    const inputs = CHAIN_IDS.flatMap((chain) => {
      const row = rowAt(byChain[chain], t);
      if (!row) return [];
      const rowT = row.hourStart.getTime();
      const history = byChain[chain]
        .filter((r) => r.hourStart.getTime() < rowT && r.hourStart.getTime() >= rowT - HISTORY_HOURS * HOUR_MS)
        .map(toSample);
      return [{ chain, current: toSample(row), history }];
    });
    return computeActivityIndex(inputs);
  };

  const histories: Record<ChainId, number[]> = { solana: [], bsc: [], robinhood: [] };
  for (let k = SPARKLINE_HOURS - 1; k >= 1; k--) {
    for (const r of indexAt(currentHour - k * HOUR_MS)) histories[r.chain].push(r.index);
  }

  return indexAt(currentHour).map((r) => {
    const latest = rowAt(byChain[r.chain], currentHour)!;
    histories[r.chain].push(r.index);
    return {
      chain: r.chain,
      activityIndex: r.index,
      label: r.label,
      momentum: r.momentum,
      dominance: r.dominance,
      volumeShare: r.volumeShare,
      metrics: toSample(latest),
      heat: r.heat,
      indexHistory: histories[r.chain],
    };
  });
}

function buildLaunches(raw: RawDashboardData, thresholdUsd: number): LaunchReport {
  const today = floorToDay(raw.now).getTime();
  const days = Array.from({ length: 30 }, (_, i) => dayKey(new Date(today - (29 - i) * DAY_MS)));
  const byKey = new Map(raw.launches.map((l) => [`${l.chain}:${l.day}`, l]));
  const count = (chain: ChainId, day: string) => byKey.get(`${chain}:${day}`)?.crossed100k ?? 0;

  const points: LaunchDayPoint[] = days.map((date) => ({
    date,
    solana: count('solana', date),
    bsc: count('bsc', date),
    robinhood: count('robinhood', date),
  }));

  const todayKey = days[days.length - 1]!;
  const yesterdayKey = days[days.length - 2]!;
  const prev7 = days.slice(-8, -1);

  const todayReport = {} as LaunchReport['today'];
  for (const chain of CHAIN_IDS) {
    const breakdown = byKey.get(`${chain}:${todayKey}`)?.byLaunchpad ?? {};
    const entries = Object.entries(breakdown) as [Launchpad, number][];
    const total = entries.reduce((a, [, n]) => a + n, 0);
    const top = entries.sort((a, b) => b[1] - a[1])[0];
    todayReport[chain] = {
      count: count(chain, todayKey),
      yesterday: count(chain, yesterdayKey),
      avg7d: mean(prev7.map((d) => count(chain, d))),
      topLaunchpad: top && total > 0 ? { launchpad: top[0], share: top[1] / total } : null,
    };
  }

  return {
    days: points,
    today: todayReport,
    dayProgress: (raw.now.getTime() - today) / DAY_MS,
    thresholdUsd,
  };
}

function buildTrade(raw: RawDashboardData): TradeWindowReport {
  const byChain = groupByChain<RawHour>(raw.hours);
  const series: Record<MatrixKey, RawHour[]> = {
    ...byChain,
    all: mergeBuckets(CHAIN_IDS.map((c) => byChain[c])) as RawHour[],
  };
  const currentHour = floorToHour(raw.now).getTime();
  const keys: MatrixKey[] = [...CHAIN_IDS, 'all'];

  const report = { weeks: MATRIX_WEEKS, matrices: {}, now: {}, recent: {}, best: {} } as TradeWindowReport;
  for (const key of keys) {
    const buckets = series[key];
    const cells = buildHeatMatrix(buckets, raw.now);
    const live = buckets.find((b) => b.hourStart.getTime() === currentHour) ?? null;
    const recent = hottestRecentHour(buckets, raw.now);
    report.matrices[key] = cells;
    report.now[key] = currentStatus(cells, raw.now, live ? live.volumeUsd : null);
    report.recent[key] = recent
      ? { hourStart: recent.hourStart.toISOString(), volumeUsd: recent.volumeUsd, txCount: recent.txCount }
      : null;
    report.best[key] = bestWindow(cells);
  }
  return report;
}

interface SocialAgg {
  mentions24h: number;
  mentionsPrev24h: number;
  engagements24h: number;
  sentiment: number | null;
  series: number[];
}

function aggregateSocial(raw: RawDashboardData): Map<string, SocialAgg> {
  const currentHour = floorToHour(raw.now).getTime();
  const firstHour = currentHour - (SPARKLINE_HOURS - 1) * HOUR_MS;
  const prevFirst = firstHour - SPARKLINE_HOURS * HOUR_MS;
  const out = new Map<string, SocialAgg & { sentWeight: number; sentTotal: number }>();

  for (const s of raw.social) {
    const t = s.hourStart.getTime();
    if (t < prevFirst || t > currentHour) continue;
    const key = `${s.chain}:${s.address}`;
    const agg = out.get(key) ?? {
      mentions24h: 0,
      mentionsPrev24h: 0,
      engagements24h: 0,
      sentiment: null,
      series: new Array<number>(SPARKLINE_HOURS).fill(0),
      sentWeight: 0,
      sentTotal: 0,
    };
    if (t >= firstHour) {
      agg.mentions24h += s.mentions;
      agg.engagements24h += s.engagements;
      agg.series[(t - firstHour) / HOUR_MS] = (agg.series[(t - firstHour) / HOUR_MS] ?? 0) + s.mentions;
      if (s.sentiment !== null) {
        const w = Math.max(1, s.engagements);
        agg.sentTotal += s.sentiment * w;
        agg.sentWeight += w;
      }
    } else {
      agg.mentionsPrev24h += s.mentions;
    }
    out.set(key, agg);
  }

  const result = new Map<string, SocialAgg>();
  for (const [key, { sentWeight, sentTotal, ...agg }] of out) {
    result.set(key, { ...agg, sentiment: sentWeight > 0 ? sentTotal / sentWeight : null });
  }
  return result;
}

const EMPTY_SOCIAL: SocialAgg = {
  mentions24h: 0,
  mentionsPrev24h: 0,
  engagements24h: 0,
  sentiment: null,
  series: new Array<number>(SPARKLINE_HOURS).fill(0),
};

function buildWhales(raw: RawDashboardData, minUsd: number): WhaleReport {
  const trades = [...raw.whales].sort((a, b) => b.blockTime.getTime() - a.blockTime.getTime());
  return {
    trades: trades.slice(0, 25).map((t) => ({ ...t, blockTime: t.blockTime.toISOString() })),
    netFlow1h: netFlow(trades, new Date(raw.now.getTime() - HOUR_MS)),
    minUsd,
  };
}

export function buildSnapshot(
  raw: RawDashboardData,
  options: SnapshotOptions = DEFAULT_SNAPSHOT_OPTIONS,
): DashboardSnapshot {
  const social = aggregateSocial(raw);
  const socialOf = (chain: ChainId, address: string) => social.get(`${chain}:${address}`) ?? EMPTY_SOCIAL;

  const narratives = computeNarrativeTrends(
    raw.tokens.map((t) => {
      const s = socialOf(t.chain, t.address);
      return {
        symbol: t.symbol,
        narratives: t.narratives,
        volume24hUsd: t.volume24hUsd ?? 0,
        priceChange24hPct: t.priceChange24hPct,
        poolCreatedAt: t.poolCreatedAt,
        mentions24h: s.mentions24h,
        mentionsPrev24h: s.mentionsPrev24h,
        mentionSeries: s.series,
      };
    }),
    raw.now,
  );

  const candidates: HypeCandidate[] = raw.tokens.flatMap((t) => {
    if (t.marketCapUsd === null || t.liquidityUsd === null || t.volume24hUsd === null) return [];
    const s = socialOf(t.chain, t.address);
    return [
      {
        chain: t.chain,
        address: t.address,
        symbol: t.symbol,
        name: t.name,
        narratives: t.narratives,
        launchpad: t.launchpad,
        priceUsd: t.priceUsd,
        priceChange24hPct: t.priceChange24hPct,
        marketCapUsd: t.marketCapUsd,
        liquidityUsd: t.liquidityUsd,
        volume24hUsd: t.volume24hUsd,
        mentions24h: s.mentions24h,
        mentionsPrev24h: s.mentionsPrev24h,
        engagements24h: s.engagements24h,
        sentiment: s.sentiment,
        mentionSeries: s.series,
        poolCreatedAt: t.poolCreatedAt,
      },
    ];
  });
  const hype = scoreHype(candidates, raw.now);

  const ticker: TickerItem[] = candidates
    .filter(
      (c) =>
        c.priceChange24hPct !== null &&
        c.liquidityUsd >= DEFAULT_HYPE_FILTERS.minLiquidityUsd &&
        c.marketCapUsd >= DEFAULT_HYPE_FILTERS.minMarketCapUsd,
    )
    .sort((a, b) => (b.priceChange24hPct ?? 0) - (a.priceChange24hPct ?? 0))
    .slice(0, 12)
    .map((c) => ({
      chain: c.chain,
      symbol: c.symbol,
      priceChange24hPct: c.priceChange24hPct ?? 0,
      volume24hUsd: c.volume24hUsd,
    }));

  return {
    generatedAt: raw.now.toISOString(),
    mode: raw.mode,
    chains: buildChains(raw),
    launches: buildLaunches(raw, options.milestoneUsd),
    trade: buildTrade(raw),
    narratives,
    risingNarrative: narratives[0] ?? null,
    // Wash-trade şüphelisi (aşırı devir) token taç giyemez; listede görünmeye devam eder.
    coinOfTheDay: hype.find((h) => !h.riskFlags.includes('asiri-devir')) ?? hype[0] ?? null,
    hypeLeaders: hype.slice(0, 6),
    whales: buildWhales(raw, options.whaleMinUsd),
    ticker,
  };
}
