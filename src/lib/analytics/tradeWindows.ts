// En aktif trade zamanı — 24 saat × 7 gün ısı matrisi
//
// 1. Son N haftanın (varsayılan 4) kapanmış saatlik kovaları (VolumeByHour), UTC
//    haftanın saatine (gün × 24 + saat) göre 168 hücreye dağıtılır.
// 2. Her hücrede MEDYAN hacim/volatilite alınır (tek bir pump saati hücreyi boyamasın),
//    insan payı = insan tx / (insan + bot tx).
// 3. Bileşenler hücreler arası persentile çevrilir ve ağırlıklanır:
//      skor = 0.55 × hacim + 0.25 × volatilite + 0.20 × insan payı
//    Hacim likiditeyi (kayma), volatilite fırsatı, insan payı ise bot gürültüsü dışındaki
//    gerçek talebi temsil eder.
// 4. Skorlar min–max ile 0–1'e ölçeklenir → hücre sıcaklığı (haftaya göre göreli).

import type { MatrixCell, TradeLevel } from '../types';
import {
  DAY_MS,
  HOUR_MS,
  clamp,
  floorToHour,
  median,
  percentileRank,
  sum,
  utcDow,
  weightedMean,
} from './stats';

export interface HourBucket {
  hourStart: Date;
  volumeUsd: number;
  txCount: number;
  botTxCount: number;
  humanTxCount: number;
  volatilityPct: number;
}

export const CELLS_PER_WEEK = 168;
export const MATRIX_WEEKS = 4;
export const TRADE_HEAT_WEIGHTS = { volume: 0.55, volatility: 0.25, human: 0.2 } as const;
export const BEST_WINDOW_HOURS = 3;

export function cellIndex(date: Date): number {
  return utcDow(date) * 24 + date.getUTCHours();
}

/** Birden çok zincirin kovalarını saat bazında birleştirir (volatilite hacim ağırlıklı). */
export function mergeBuckets(lists: ReadonlyArray<readonly HourBucket[]>): HourBucket[] {
  const byHour = new Map<number, HourBucket & { volWeight: number }>();
  for (const list of lists) {
    for (const b of list) {
      const key = b.hourStart.getTime();
      const acc = byHour.get(key) ?? {
        hourStart: b.hourStart,
        volumeUsd: 0,
        txCount: 0,
        botTxCount: 0,
        humanTxCount: 0,
        volatilityPct: 0,
        volWeight: 0,
      };
      acc.volumeUsd += b.volumeUsd;
      acc.txCount += b.txCount;
      acc.botTxCount += b.botTxCount;
      acc.humanTxCount += b.humanTxCount;
      acc.volWeight += b.volatilityPct * b.volumeUsd;
      byHour.set(key, acc);
    }
  }
  return [...byHour.values()]
    .sort((a, b) => a.hourStart.getTime() - b.hourStart.getTime())
    .map(({ volWeight, ...b }) => ({
      ...b,
      volatilityPct: b.volumeUsd > 0 ? volWeight / b.volumeUsd : 0,
    }));
}

export function buildHeatMatrix(
  buckets: readonly HourBucket[],
  now: Date,
  weeks: number = MATRIX_WEEKS,
): MatrixCell[] {
  const currentHour = floorToHour(now).getTime();
  const from = currentHour - weeks * 7 * DAY_MS;
  const groups: HourBucket[][] = Array.from({ length: CELLS_PER_WEEK }, () => []);
  for (const b of buckets) {
    const t = b.hourStart.getTime();
    // İçinde bulunulan saat henüz kapanmadı; matrise alınmaz.
    if (t < from || t >= currentHour) continue;
    groups[cellIndex(b.hourStart)]!.push(b);
  }

  const raw = groups.map((g) => {
    const human = sum(g.map((b) => b.humanTxCount));
    const bot = sum(g.map((b) => b.botTxCount));
    return {
      samples: g.length,
      volumeUsd: median(g.map((b) => b.volumeUsd)),
      txCount: Math.round(median(g.map((b) => b.txCount))),
      volatilityPct: median(g.map((b) => b.volatilityPct)),
      humanShare: human + bot > 0 ? human / (human + bot) : null,
    };
  });

  const filled = raw.filter((c) => c.samples > 0);
  const volumes = filled.map((c) => c.volumeUsd);
  const volatilities = filled.map((c) => c.volatilityPct);
  const humanShares = filled.flatMap((c) => (c.humanShare === null ? [] : [c.humanShare]));

  const scores = raw.map((c) =>
    c.samples === 0
      ? null
      : weightedMean([
          { value: percentileRank(c.volumeUsd, volumes), weight: TRADE_HEAT_WEIGHTS.volume },
          { value: percentileRank(c.volatilityPct, volatilities), weight: TRADE_HEAT_WEIGHTS.volatility },
          {
            value: c.humanShare === null ? null : percentileRank(c.humanShare, humanShares),
            weight: TRADE_HEAT_WEIGHTS.human,
          },
        ]),
  );
  const present = scores.filter((s): s is number => s !== null);
  const lo = present.length ? Math.min(...present) : 0;
  const hi = present.length ? Math.max(...present) : 0;

  return raw.map((c, i) => {
    const s = scores[i];
    const heat = s === null || s === undefined ? 0 : hi > lo ? (s - lo) / (hi - lo) : 0.5;
    return { ...c, heat };
  });
}

/** Haftanın en sıcak `length` saatlik kesintisiz penceresi (hafta sonundan başa sarar). */
export function bestWindow(cells: readonly MatrixCell[], length: number = BEST_WINDOW_HOURS) {
  let best = { dow: 0, startHour: 0, length, avgHeat: -1 };
  for (let start = 0; start < CELLS_PER_WEEK; start++) {
    let total = 0;
    for (let k = 0; k < length; k++) total += cells[(start + k) % CELLS_PER_WEEK]?.heat ?? 0;
    const avgHeat = total / length;
    if (avgHeat > best.avgHeat) {
      best = { dow: Math.floor(start / 24), startHour: start % 24, length, avgHeat };
    }
  }
  return best;
}

/**
 * "Şu an aktif trade saati mi?"
 * Seviye, bu haftanın-saatinin tarihsel sıcaklığından gelir; canlı saat hacmi
 * hücre medyanının ≥1.5 katıysa bir kademe yükselir, ≤0.6 katıysa bir kademe düşer.
 */
export function currentStatus(
  cells: readonly MatrixCell[],
  now: Date,
  liveVolumeUsd: number | null,
): { heat: number; level: TradeLevel; liveRatio: number | null } {
  const cell = cells[cellIndex(now)];
  const heat = cell?.heat ?? 0;
  const liveRatio =
    liveVolumeUsd !== null && cell && cell.samples > 0 && cell.volumeUsd > 0
      ? liveVolumeUsd / cell.volumeUsd
      : null;

  const levels: TradeLevel[] = ['sakin', 'normal', 'aktif'];
  let rank = heat >= 0.66 ? 2 : heat >= 0.33 ? 1 : 0;
  if (liveRatio !== null && liveRatio >= 1.5) rank++;
  if (liveRatio !== null && liveRatio <= 0.6) rank--;
  return { heat, level: levels[clamp(rank, 0, 2)]!, liveRatio };
}

/** Son `hours` saatlik kova (içinde bulunulan saat dahil) içindeki en yüksek hacimli saat. */
export function hottestRecentHour(buckets: readonly HourBucket[], now: Date, hours = 4) {
  const currentHour = floorToHour(now).getTime();
  const from = currentHour - (hours - 1) * HOUR_MS;
  let best: HourBucket | null = null;
  for (const b of buckets) {
    const t = b.hourStart.getTime();
    if (t < from || t > currentHour) continue;
    if (!best || b.volumeUsd > best.volumeUsd) best = b;
  }
  return best;
}

/**
 * UTC matrisini yerel saate çevirir: yerel hücre i, UTC hücresi (i − offset) mod 168'dir.
 * Tam saat olmayan dilimler (ör. UTC+5:30) en yakın saate yuvarlanmalıdır.
 */
export function rotateCells<T>(cells: readonly T[], offsetHours: number): T[] {
  const n = cells.length;
  const shift = ((Math.round(offsetHours) % n) + n) % n;
  return cells.map((_, i) => cells[(i - shift + n) % n]!);
}
