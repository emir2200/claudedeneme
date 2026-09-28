// Görsel kodlama sabitleri. Renkler hesaplanıp doğrulandı; göz kararı değiştirmeyin.
//
// Isı rampası: "semantik ısı" sıralı ölçeği (koyu bordo → turuncu → sarı). OKLCH'de açıklık
// 0.26 → 0.91 tekdüze artar (L monoton), düşük uç panel yüzeyine doğru kaybolur. Sayısal
// değerler ayrıca metin/tablo olarak da sunulur; renk tek bilgi kanalı değildir.

export const HEAT_RAMP = ['#401314', '#6a2718', '#954009', '#b66304', '#d58a08', '#f1b206', '#ffe069'] as const;

/** Verisi olmayan hücre (nötr, rampadan ayrışır). */
export const HEAT_EMPTY = '#1b1f29';

export function heatStep(t: number): number {
  const clamped = Math.min(1, Math.max(0, t));
  return Math.min(HEAT_RAMP.length - 1, Math.floor(clamped * HEAT_RAMP.length));
}

export function heatColor(t: number | null | undefined): string {
  return t === null || t === undefined || !Number.isFinite(t) ? HEAT_EMPTY : HEAT_RAMP[heatStep(t)]!;
}

/** Hücre üstü metin: ilk dört kademede açık, sonrakilerde koyu mürekkep (≥ 4.4:1). */
export function heatInk(t: number | null | undefined): string {
  if (t === null || t === undefined || !Number.isFinite(t)) return '#aeb4c2';
  return heatStep(t) <= 3 ? '#ffffff' : '#0b0d12';
}
