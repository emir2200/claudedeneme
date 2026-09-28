// Bir chain'in gün içindeki en aktif trade saatleri
//
// Girdi: chain'deki en yüksek hacimli havuzların saatlik hacmi (GeckoTerminal OHLCV),
// saat bazında toplanır. Çıktılar:
//   - Tipik gün profili: her UTC saat için son N günün MEDYAN hacmi. Medyan, tek bir
//     olağandışı günün (listeleme, çöküş) profili bozmasını önler.
//   - En yoğun / en sakin 3 saatlik pencere (gece yarısından sarar).
//   - Haftalık 7 × 24 matris: haftanın her saati için son 4 haftanın medyanı.
//   - "Şu an": son tamamlanan saatin hacmi, o saatin tipik hacmine oranla.
// Tüm hesaplar UTC'dir; arayüz yerel saate çevirir.

import type { ActivityLevel, HourProfilePoint, MatrixCell } from '../types';
import { DAY_MS, HOUR_MS, floorToDay, floorToHour, median, utcDow } from './stats';

export interface HourlyPoint {
  /** Saat başlangıcı (epoch ms, UTC). */
  hourStart: number;
  volumeUsd: number;
}

export const PROFILE_DAYS = 28;
export const WINDOW_HOURS = 3;

/** Birden çok havuzun saatlik serisini saat bazında toplar. */
export function mergeHourly(seriesList: ReadonlyArray<readonly HourlyPoint[]>): HourlyPoint[] {
  const byHour = new Map<number, number>();
  for (const series of seriesList) {
    for (const p of series) {
      if (!Number.isFinite(p.volumeUsd)) continue;
      byHour.set(p.hourStart, (byHour.get(p.hourStart) ?? 0) + p.volumeUsd);
    }
  }
  return [...byHour.entries()].sort(([a], [b]) => a - b).map(([hourStart, volumeUsd]) => ({ hourStart, volumeUsd }));
}

/**
 * [ilk veri saati, şimdiki saat) aralığındaki TAMAMLANMIŞ saatleri, işlem olmayan saatler 0
 * olacak şekilde doldurur. En fazla `days` gün geriye gider.
 */
export function completeHourGrid(points: readonly HourlyPoint[], now: Date, days = PROFILE_DAYS): HourlyPoint[] {
  const end = floorToHour(now).getTime();
  const earliest = end - days * DAY_MS;
  const inRange = points.filter((p) => p.hourStart >= earliest && p.hourStart < end);
  if (inRange.length === 0) return [];
  const byHour = new Map(inRange.map((p) => [p.hourStart, p.volumeUsd]));
  const start = Math.min(...inRange.map((p) => p.hourStart));
  const grid: HourlyPoint[] = [];
  for (let t = start; t < end; t += HOUR_MS) grid.push({ hourStart: t, volumeUsd: byHour.get(t) ?? 0 });
  return grid;
}

function minMax(values: readonly number[]): (v: number) => number {
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  return (v) => (hi > lo ? (v - lo) / (hi - lo) : 0.5);
}

export function hourProfile(grid: readonly HourlyPoint[]): HourProfilePoint[] {
  const buckets: number[][] = Array.from({ length: 24 }, () => []);
  for (const p of grid) buckets[new Date(p.hourStart).getUTCHours()]!.push(p.volumeUsd);
  const medians = buckets.map((b) => median(b));
  const total = medians.reduce((a, v) => a + v, 0);
  const scale = minMax(medians);
  return medians.map((m, hour) => ({
    hour,
    medianVolumeUsd: m,
    share: total > 0 ? m / total : 0,
    heat: buckets[hour]!.length ? scale(m) : 0,
  }));
}

/** 24 saatlik profilde, en yüksek (veya en düşük) paylı kesintisiz pencere. */
export function dayWindow(profile: readonly HourProfilePoint[], mode: 'max' | 'min', length = WINDOW_HOURS) {
  let best = { startHour: 0, length, share: mode === 'max' ? -Infinity : Infinity };
  for (let start = 0; start < 24; start++) {
    let share = 0;
    for (let k = 0; k < length; k++) share += profile[(start + k) % 24]!.share;
    if (mode === 'max' ? share > best.share : share < best.share) best = { startHour: start, length, share };
  }
  return best;
}

export function weekMatrix(grid: readonly HourlyPoint[]): MatrixCell[] {
  const buckets: number[][] = Array.from({ length: 168 }, () => []);
  for (const p of grid) {
    const d = new Date(p.hourStart);
    buckets[utcDow(d) * 24 + d.getUTCHours()]!.push(p.volumeUsd);
  }
  const medians = buckets.map((b) => median(b));
  const filled = medians.filter((_, i) => buckets[i]!.length > 0);
  const scale = filled.length ? minMax(filled) : () => 0;
  return medians.map((m, i) => ({
    heat: buckets[i]!.length ? scale(m) : 0,
    volumeUsd: m,
    samples: buckets[i]!.length,
  }));
}

/**
 * Son tamamlanan saatin durumu. Seviye önce o saatin tipik sıcaklığından gelir
 * (≥0.66 aktif, ≥0.33 normal, altı sakin); hacim tipiğinin ≥1,5 katıysa bir kademe
 * yükselir, ≤0,6 katıysa bir kademe düşer.
 */
export function lastHourStatus(grid: readonly HourlyPoint[], profile: readonly HourProfilePoint[]) {
  const last = grid.at(-1);
  if (!last) return null;
  const point = profile[new Date(last.hourStart).getUTCHours()]!;
  const ratio = point.medianVolumeUsd > 0 ? last.volumeUsd / point.medianVolumeUsd : null;
  const levels: ActivityLevel[] = ['sakin', 'normal', 'aktif'];
  let rank = point.heat >= 0.66 ? 2 : point.heat >= 0.33 ? 1 : 0;
  if (ratio !== null && ratio >= 1.5) rank++;
  if (ratio !== null && ratio <= 0.6) rank--;
  return {
    hourStart: new Date(last.hourStart).toISOString(),
    volumeUsd: last.volumeUsd,
    typicalUsd: point.medianVolumeUsd,
    ratio,
    level: levels[Math.min(2, Math.max(0, rank))]!,
  };
}

/** Bugünün (UTC) tamamlanan saatlerinin hacmi; gelmemiş saatler null. */
export function todaySeries(grid: readonly HourlyPoint[], now: Date): Array<number | null> {
  const dayStart = floorToDay(now).getTime();
  const out: Array<number | null> = new Array(24).fill(null);
  for (const p of grid) {
    if (p.hourStart >= dayStart) out[new Date(p.hourStart).getUTCHours()] = p.volumeUsd;
  }
  return out;
}

/** UTC hücre dizisini yerel saate döndürür: yerel i = UTC (i − ofset). */
export function rotate<T>(cells: readonly T[], offsetHours: number): T[] {
  const n = cells.length;
  const shift = ((Math.round(offsetHours) % n) + n) % n;
  return cells.map((_, i) => cells[(i - shift + n) % n]!);
}
