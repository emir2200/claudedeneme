// Türkçe sayı / para / zaman biçimlendiricileri (UI).

const integer = new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 0 });
const oneDecimal = new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 1 });

/**
 * Kısa sayı: 340 bin · 1,2 Mn · 12,3 Mr. Türkçe "B" (bin) kısaltması kriptoda "billion"
 * ile karıştırılacağı için kullanılmaz.
 */
function compact(value: number): string {
  const abs = Math.abs(value);
  if (abs >= 1e9) return `${oneDecimal.format(value / 1e9)} Mr`;
  if (abs >= 1e6) return `${oneDecimal.format(value / 1e6)} Mn`;
  if (abs >= 1e3) return `${oneDecimal.format(value / 1e3)} bin`;
  return integer.format(value);
}

/** $340 bin · $1,2 Mn · $12,3 Mr */
export function formatUsd(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—';
  return `$${compact(value)}`;
}

/** İşaretli yüzde (Türkçe yazım): +%12,4 / −%3,1 */
export function formatPct(value: number | null | undefined, digits = 1): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—';
  const abs = Math.abs(value).toLocaleString('tr-TR', { maximumFractionDigits: digits, minimumFractionDigits: digits });
  return `${value > 0 ? '+' : value < 0 ? '−' : ''}%${abs}`;
}

export function formatRatio(value: number, digits = 2): string {
  return `${value.toLocaleString('tr-TR', { maximumFractionDigits: digits })}×`;
}

export const DAY_NAMES = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'] as const;
export const DAY_NAMES_LONG = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'] as const;

export const hourLabel = (h: number) => `${String(((h % 24) + 24) % 24).padStart(2, '0')}:00`;

export function formatUtcOffset(offset: number): string {
  return offset === 0 ? 'UTC' : `UTC${offset > 0 ? '+' : '−'}${Math.abs(offset)}`;
}

/** 2026-09-28 → 28 Eyl */
export function shortDate(day: string): string {
  return new Date(`${day}T00:00:00Z`).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short', timeZone: 'UTC' });
}
