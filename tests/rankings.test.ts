import { describe, expect, it } from 'vitest';
import { buildRankings, completeDays, periodTotals, type ChainVolumeInput, type DailyPoint } from '@/lib/analytics/rankings';

/** `count` gün, bitişi `lastDay` olan sabit hacimli seri. */
function series(count: number, perDay: (i: number) => number, lastDay = '2026-09-27'): DailyPoint[] {
  const end = Date.parse(`${lastDay}T00:00:00Z`);
  return Array.from({ length: count }, (_, i) => ({
    day: new Date(end - (count - 1 - i) * 86_400_000).toISOString().slice(0, 10),
    volumeUsd: perDay(i),
  }));
}

const noFallback: ChainVolumeInput['fallback'] = { total24h: null, total7d: null, total30d: null };
const input = (chain: string, s: DailyPoint[], fallback = noFallback): ChainVolumeInput => ({ chain, name: chain, series: s, fallback });

describe('completeDays', () => {
  it('bugünü (bitmemiş gün) atar, sıralar ve tekilleştirir', () => {
    const days = completeDays(
      [
        { day: '2026-09-28', volumeUsd: 1 },
        { day: '2026-09-26', volumeUsd: 2 },
        { day: '2026-09-27', volumeUsd: 3 },
        { day: '2026-09-27', volumeUsd: 4 },
      ],
      '2026-09-28',
    );
    expect(days).toEqual([
      { day: '2026-09-26', volumeUsd: 2 },
      { day: '2026-09-27', volumeUsd: 4 },
    ]);
  });
});

describe('periodTotals', () => {
  it('gün/hafta/ay pencerelerini ve önceki dönemleri hesaplar', () => {
    // 60 gün: ilk 30 gün 1, son 30 gün 2; son gün 10.
    const s = series(60, (i) => (i === 59 ? 10 : i >= 30 ? 2 : 1));
    const t = periodTotals(input('x', s), '2026-09-28');
    expect(t.lastDay).toBe('2026-09-27');
    expect(t.day).toEqual({ value: 10, prev: 2 });
    expect(t.week).toEqual({ value: 10 + 6 * 2, prev: 14 });
    expect(t.month).toEqual({ value: 10 + 29 * 2, prev: 30 });
  });

  it('yeterli gün yoksa sağlayıcının toplamına döner, önceki dönem bilinmez', () => {
    const t = periodTotals(input('yeni', series(3, () => 5), { total24h: 5, total7d: 15, total30d: 15 }), '2026-09-28');
    expect(t.day).toEqual({ value: 5, prev: 5 });
    expect(t.week).toEqual({ value: 15, prev: null });
    expect(t.month).toEqual({ value: 15, prev: null });
  });
});

describe('buildRankings', () => {
  it('her dönemi ayrı sıralar, payları ve değişimleri hesaplar', () => {
    const { rows, asOfDay } = buildRankings(
      [
        // A: ay boyunca büyük ama son gün düşük
        input('A', series(60, (i) => (i === 59 ? 1 : 10))),
        // B: ay boyunca küçük ama son gün patlamış
        input('B', series(60, (i) => (i === 59 ? 50 : 2))),
        // Veri yok: sıralamaya girmez
        input('C', []),
      ],
      '2026-09-28',
    );
    expect(asOfDay).toBe('2026-09-27');
    expect(rows.map((r) => r.chain)).toEqual(['B', 'A']);
    const [b, a] = rows;
    expect(b!.stats.day).toMatchObject({ rank: 1, volumeUsd: 50, changePct: 2400 });
    expect(a!.stats.month.rank).toBe(1);
    expect(b!.stats.month.rank).toBe(2);
    expect(a!.stats.day.share + b!.stats.day.share).toBeCloseTo(1);
    expect(a!.last30).toHaveLength(30);
  });
});
