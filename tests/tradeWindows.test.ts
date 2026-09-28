import { describe, expect, it } from 'vitest';
import { HOUR_MS } from '@/lib/analytics/stats';
import {
  bestWindow,
  buildHeatMatrix,
  cellIndex,
  currentStatus,
  hottestRecentHour,
  mergeBuckets,
  rotateCells,
  type HourBucket,
} from '@/lib/analytics/tradeWindows';

// 2026-09-28 bir Pazartesi.
const now = new Date('2026-09-28T12:30:00Z');

function weeksOfBuckets(weeks: number, volumeFor: (d: Date) => number): HourBucket[] {
  const end = Date.UTC(2026, 8, 28, 12);
  const out: HourBucket[] = [];
  for (let t = end - weeks * 168 * HOUR_MS; t <= end; t += HOUR_MS) {
    const hourStart = new Date(t);
    out.push({ hourStart, volumeUsd: volumeFor(hourStart), txCount: 100, botTxCount: 50, humanTxCount: 50, volatilityPct: 5 });
  }
  return out;
}

describe('buildHeatMatrix', () => {
  it('168 hücre üretir; en yoğun saat en sıcak hücre olur', () => {
    const buckets = weeksOfBuckets(5, (d) => (d.getUTCHours() === 15 ? 1_000 : 100));
    const cells = buildHeatMatrix(buckets, now);
    expect(cells).toHaveLength(168);
    const hottest = cells.reduce((best, c, i) => (c.heat > cells[best]!.heat ? i : best), 0);
    expect(hottest % 24).toBe(15);
    expect(Math.max(...cells.map((c) => c.heat))).toBe(1);
    expect(cells.every((c) => c.samples === 4)).toBe(true);
  });

  it('medyan kullanır: tek bir aşırı saat hücreyi boyamaz', () => {
    const outlier = new Date('2026-09-14T03:00:00Z').getTime();
    const buckets = weeksOfBuckets(5, (d) => (d.getTime() === outlier ? 1e9 : d.getUTCHours() === 15 ? 1_000 : 100));
    const cells = buildHeatMatrix(buckets, now);
    expect(cells[cellIndex(new Date(outlier))]!.volumeUsd).toBe(100);
  });

  it('içinde bulunulan (kapanmamış) saati matrise almaz', () => {
    const current = { hourStart: new Date('2026-09-28T12:00:00Z'), volumeUsd: 1e12, txCount: 1, botTxCount: 0, humanTxCount: 1, volatilityPct: 1 };
    const cells = buildHeatMatrix([current], now);
    expect(cells.every((c) => c.samples === 0)).toBe(true);
  });
});

describe('bestWindow', () => {
  it('hafta sonundan başa saran pencereyi bulur', () => {
    const cells = Array.from({ length: 168 }, (_, i) => ({
      heat: i >= 166 || i === 0 ? 1 : 0,
      volumeUsd: 0,
      txCount: 0,
      humanShare: null,
      volatilityPct: 0,
      samples: 1,
    }));
    expect(bestWindow(cells, 3)).toMatchObject({ dow: 6, startHour: 22, avgHeat: 1 });
  });
});

describe('currentStatus', () => {
  const cells = Array.from({ length: 168 }, () => ({ heat: 0.5, volumeUsd: 100, txCount: 0, humanShare: null, volatilityPct: 0, samples: 4 }));
  it('canlı hacim medyanın 1.5 katıysa bir kademe yükselir', () => {
    expect(currentStatus(cells, now, 160)).toMatchObject({ level: 'aktif', liveRatio: 1.6 });
    expect(currentStatus(cells, now, 100).level).toBe('normal');
    expect(currentStatus(cells, now, 50).level).toBe('sakin');
    expect(currentStatus(cells, now, null).liveRatio).toBeNull();
  });
});

describe('yardımcılar', () => {
  it('hottestRecentHour son 4 kova içinden en yükseği seçer', () => {
    const buckets = weeksOfBuckets(1, (d) => (d.getUTCHours() === 10 ? 999 : d.getUTCHours() === 5 ? 5_000 : 1));
    expect(hottestRecentHour(buckets, now)!.hourStart.toISOString()).toBe('2026-09-28T10:00:00.000Z');
  });

  it('mergeBuckets hacimleri toplar, volatiliteyi hacimle ağırlıklar', () => {
    const h = new Date('2026-09-28T01:00:00Z');
    const [m] = mergeBuckets([
      [{ hourStart: h, volumeUsd: 300, txCount: 3, botTxCount: 1, humanTxCount: 2, volatilityPct: 10 }],
      [{ hourStart: h, volumeUsd: 100, txCount: 1, botTxCount: 1, humanTxCount: 0, volatilityPct: 2 }],
    ]);
    expect(m).toMatchObject({ volumeUsd: 400, txCount: 4, botTxCount: 2, humanTxCount: 2, volatilityPct: 8 });
  });

  it('rotateCells UTC+3 için Pazartesi 00:00 UTC hücresini 03:00 yerel hücresine taşır', () => {
    const cells = Array.from({ length: 168 }, (_, i) => i);
    const local = rotateCells(cells, 3);
    expect(local[3]).toBe(0);
    expect(local[0]).toBe(165);
    expect(rotateCells(cells, -24 * 7)).toEqual(cells);
  });
});
