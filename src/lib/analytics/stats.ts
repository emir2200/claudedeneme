// Küçük, bağımlılıksız istatistik yardımcıları. Tüm analitik modülleri bunları kullanır.

export const HOUR_MS = 3_600_000;
export const DAY_MS = 24 * HOUR_MS;

export function clamp(x: number, lo = 0, hi = 1): number {
  return Math.min(hi, Math.max(lo, x));
}

export function sum(xs: readonly number[]): number {
  let s = 0;
  for (const x of xs) s += x;
  return s;
}

export function mean(xs: readonly number[]): number {
  return xs.length === 0 ? 0 : sum(xs) / xs.length;
}

export function median(xs: readonly number[]): number {
  if (xs.length === 0) return 0;
  const sorted = [...xs].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid]! : (sorted[mid - 1]! + sorted[mid]!) / 2;
}

/**
 * Ampirik persentil sırası (0–1), eşitlikler için orta-sıra:
 * (altındakiler + 0.5 × eşitler) / n. Örneklem boşsa 0.5 (nötr) döner.
 * Ölçek bağımsızdır ve uç değerlere (tek bir pump saati) karşı dayanıklıdır.
 */
export function percentileRank(value: number, sample: readonly number[]): number {
  if (sample.length === 0) return 0.5;
  let below = 0;
  let equal = 0;
  for (const x of sample) {
    if (x < value) below++;
    else if (x === value) equal++;
  }
  return (below + 0.5 * equal) / sample.length;
}

/** Ağırlıklı ortalama; null bileşenler atlanır ve ağırlıklar yeniden normalize edilir. */
export function weightedMean(parts: ReadonlyArray<{ value: number | null; weight: number }>): number {
  let total = 0;
  let weights = 0;
  for (const { value, weight } of parts) {
    if (value === null || !Number.isFinite(value)) continue;
    total += value * weight;
    weights += weight;
  }
  return weights === 0 ? 0 : total / weights;
}

export function floorToHour(date: Date): Date {
  return new Date(Math.floor(date.getTime() / HOUR_MS) * HOUR_MS);
}

export function floorToDay(date: Date): Date {
  return new Date(Math.floor(date.getTime() / DAY_MS) * DAY_MS);
}

/** UTC `YYYY-MM-DD`. */
export function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Pazartesi = 0 … Pazar = 6 (UTC). */
export function utcDow(date: Date): number {
  return (date.getUTCDay() + 6) % 7;
}
