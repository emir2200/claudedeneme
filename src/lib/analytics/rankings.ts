// Günün, haftanın ve ayın en aktif chain'leri
//
// Aktivite ölçüsü: chain'deki tüm DEX'lerin toplam işlem hacmi (USD), DefiLlama'nın günlük
// serisinden. Dönemler kayan pencerelerdir ve yalnızca TAMAMLANMIŞ UTC günlerini içerir:
//   gün   = son tam gün          · önceki = ondan bir önceki gün
//   hafta = son 7 tam gün        · önceki = ondan önceki 7 gün
//   ay    = son 30 tam gün       · önceki = ondan önceki 30 gün
// Günlük seri yoksa (veya pencere için yeterli gün yoksa) sağlayıcının kendi 24s/7g/30g
// toplamı kullanılır; bu durumda önceki dönem bilinmez.

import { PERIODS, type ChainRanking, type Period, type PeriodStat } from '../types';

export interface DailyPoint {
  /** UTC gün, YYYY-MM-DD */
  day: string;
  volumeUsd: number;
}

export interface ChainVolumeInput {
  chain: string;
  name: string;
  series: DailyPoint[];
  fallback: { total24h: number | null; total7d: number | null; total30d: number | null };
}

export const PERIOD_DAYS: Record<Period, number> = { day: 1, week: 7, month: 30 };

/** Günleri sıralar, aynı günü tekilleştirir ve bugünü (henüz bitmemiş) atar. */
export function completeDays(series: readonly DailyPoint[], today: string): DailyPoint[] {
  const byDay = new Map<string, number>();
  for (const p of series) {
    if (p.day >= today || !Number.isFinite(p.volumeUsd)) continue;
    byDay.set(p.day, p.volumeUsd);
  }
  return [...byDay.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([day, volumeUsd]) => ({ day, volumeUsd }));
}

function windowSum(days: readonly DailyPoint[], endExclusive: number, length: number): number | null {
  const start = endExclusive - length;
  if (start < 0) return null;
  let total = 0;
  for (let i = start; i < endExclusive; i++) total += days[i]!.volumeUsd;
  return total;
}

export interface PeriodTotal {
  value: number | null;
  prev: number | null;
}

export function periodTotals(input: ChainVolumeInput, today: string): Record<Period, PeriodTotal> & { lastDay: string | null } {
  const days = completeDays(input.series, today);
  const n = days.length;
  const fallback: Record<Period, number | null> = {
    day: input.fallback.total24h,
    week: input.fallback.total7d,
    month: input.fallback.total30d,
  };
  const out = { lastDay: n ? days[n - 1]!.day : null } as Record<Period, PeriodTotal> & { lastDay: string | null };
  for (const period of PERIODS) {
    const len = PERIOD_DAYS[period];
    const value = windowSum(days, n, len);
    out[period] = value === null ? { value: fallback[period], prev: null } : { value, prev: windowSum(days, n - len, len) };
  }
  return out;
}

export function changePct(value: number, prev: number | null): number | null {
  if (prev === null || prev <= 0) return null;
  return (value / prev - 1) * 100;
}

/**
 * Chain'leri her dönem için hacme göre sıralar. Hiçbir dönemde verisi olmayan chain
 * sıralamaya girmez. Satırlar günlük sıraya göre döner.
 */
export function buildRankings(inputs: readonly ChainVolumeInput[], today: string): { rows: ChainRanking[]; asOfDay: string | null } {
  const totals = inputs
    .map((input) => ({ input, totals: periodTotals(input, today) }))
    .filter(({ totals }) => PERIODS.some((p) => totals[p].value !== null));

  const stats = new Map<string, Record<Period, PeriodStat>>();
  for (const { input } of totals) stats.set(input.chain, {} as Record<Period, PeriodStat>);

  for (const period of PERIODS) {
    const values = totals.map(({ input, totals: t }) => ({ chain: input.chain, value: t[period].value ?? 0, prev: t[period].prev }));
    const sum = values.reduce((a, v) => a + v.value, 0);
    values
      .sort((a, b) => b.value - a.value)
      .forEach((v, i) => {
        stats.get(v.chain)![period] = {
          volumeUsd: v.value,
          prevVolumeUsd: v.prev,
          changePct: changePct(v.value, v.prev),
          share: sum > 0 ? v.value / sum : 0,
          rank: i + 1,
        };
      });
  }

  const rows: ChainRanking[] = totals
    .map(({ input }) => ({
      chain: input.chain,
      name: input.name,
      stats: stats.get(input.chain)!,
      last30: completeDays(input.series, today)
        .slice(-30)
        .map((d) => d.volumeUsd),
    }))
    .sort((a, b) => a.stats.day.rank - b.stats.day.rank);

  const lastDays = totals.map(({ totals: t }) => t.lastDay).filter((d): d is string => d !== null);
  return { rows, asOfDay: lastDays.length ? lastDays.sort().at(-1)! : null };
}
