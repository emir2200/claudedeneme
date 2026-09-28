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

/** Memecoin fiyatları için anlamlı basamaklı gösterim: $0,00001234 */
export function formatPrice(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—';
  if (value >= 1) return `$${value.toLocaleString('tr-TR', { maximumFractionDigits: 2 })}`;
  return `$${value.toLocaleString('tr-TR', { maximumSignificantDigits: 4 })}`;
}

export function formatNumber(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—';
  return Math.abs(value) >= 10_000 ? compact(value) : integer.format(value);
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

export function shortAddress(address: string): string {
  return address.length <= 12 ? address : `${address.slice(0, 4)}…${address.slice(-4)}`;
}

/** Referans ana göre "3 dk önce". Sunucu ve istemci aynı referansı kullansın diye `now` parametredir. */
export function timeAgo(iso: string, now: number): string {
  const sec = Math.max(0, Math.round((now - Date.parse(iso)) / 1000));
  if (sec < 60) return `${sec} sn önce`;
  const min = Math.round(sec / 60);
  if (min < 60) return `${min} dk önce`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr} sa önce`;
  return `${Math.round(hr / 24)} gün önce`;
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
