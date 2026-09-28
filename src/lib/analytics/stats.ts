// Küçük, bağımlılıksız istatistik yardımcıları. Tüm analitik modülleri bunları kullanır.

export const HOUR_MS = 3_600_000;
export const DAY_MS = 24 * HOUR_MS;

export function median(xs: readonly number[]): number {
  if (xs.length === 0) return 0;
  const sorted = [...xs].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid]! : (sorted[mid - 1]! + sorted[mid]!) / 2;
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
