import { describe, expect, it } from 'vitest';
import { formatPct, formatUsd, hourLabel, shortDate } from '@/lib/format';

describe('biçimlendiriciler', () => {
  it('USD’yi belirsiz olmayan Türkçe kısaltmalarla yazar', () => {
    expect(formatUsd(512)).toBe('$512');
    expect(formatUsd(25_000)).toBe('$25 bin');
    expect(formatUsd(1_234_567)).toBe('$1,2 Mn');
    expect(formatUsd(12_340_000_000)).toBe('$12,3 Mr');
    expect(formatUsd(null)).toBe('—');
  });

  it('yüzdeyi ve saatleri Türkçe yazar', () => {
    expect(formatPct(12.44)).toBe('+%12,4');
    expect(formatPct(-3.06)).toBe('−%3,1');
    expect(hourLabel(25)).toBe('01:00');
    expect(hourLabel(-1)).toBe('23:00');
    expect(shortDate('2026-09-27')).toBe('27 Eyl');
  });
});
