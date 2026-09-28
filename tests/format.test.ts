import { describe, expect, it } from 'vitest';
import { formatNumber, formatPct, formatUsd, hourLabel, shortAddress, timeAgo } from '@/lib/format';

describe('biçimlendiriciler', () => {
  it('USD’yi belirsiz olmayan Türkçe kısaltmalarla yazar', () => {
    expect(formatUsd(512)).toBe('$512');
    expect(formatUsd(25_000)).toBe('$25 bin');
    expect(formatUsd(1_234_567)).toBe('$1,2 Mn');
    expect(formatUsd(12_340_000_000)).toBe('$12,3 Mr');
    expect(formatUsd(null)).toBe('—');
  });

  it('yüzdeyi Türkçe işaretli yazar', () => {
    expect(formatPct(12.44)).toBe('+%12,4');
    expect(formatPct(-3.06)).toBe('−%3,1');
    expect(formatPct(0)).toBe('%0,0');
  });

  it('diğer yardımcılar', () => {
    expect(formatNumber(9_999)).toBe('9.999');
    expect(formatNumber(45_600)).toBe('45,6 bin');
    expect(hourLabel(25)).toBe('01:00');
    expect(hourLabel(-1)).toBe('23:00');
    expect(shortAddress('0x1234567890abcdef')).toBe('0x12…cdef');
    expect(timeAgo('2026-09-28T12:00:00Z', Date.parse('2026-09-28T12:05:00Z'))).toBe('5 dk önce');
  });
});
