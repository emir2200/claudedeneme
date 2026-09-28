import { describe, expect, it } from 'vitest';
import {
  completeHourGrid,
  dayWindow,
  hourProfile,
  lastHourStatus,
  mergeHourly,
  rotate,
  todaySeries,
  weekMatrix,
  type HourlyPoint,
} from '@/lib/analytics/hours';

const H = 3_600_000;
// 2026-09-28 Pazartesi 12:30 UTC
const now = new Date('2026-09-28T12:30:00Z');
const currentHour = Date.parse('2026-09-28T12:00:00Z');

/** Son `days` günün her saati için hacim üretir (şimdiki saat hariç). */
function hours(days: number, volume: (d: Date) => number): HourlyPoint[] {
  const out: HourlyPoint[] = [];
  for (let t = currentHour - days * 24 * H; t < currentHour; t += H) out.push({ hourStart: t, volumeUsd: volume(new Date(t)) });
  return out;
}

describe('saatlik veri hazırlığı', () => {
  it('havuzları saat bazında toplar', () => {
    const merged = mergeHourly([
      [{ hourStart: 0, volumeUsd: 1 }, { hourStart: H, volumeUsd: 2 }],
      [{ hourStart: H, volumeUsd: 3 }],
    ]);
    expect(merged).toEqual([{ hourStart: 0, volumeUsd: 1 }, { hourStart: H, volumeUsd: 5 }]);
  });

  it('işlemsiz saatleri 0 ile doldurur, şimdiki (bitmemiş) saati almaz', () => {
    const grid = completeHourGrid(
      [
        { hourStart: currentHour - 3 * H, volumeUsd: 7 },
        { hourStart: currentHour - 1 * H, volumeUsd: 9 },
        { hourStart: currentHour, volumeUsd: 1_000 },
      ],
      now,
    );
    expect(grid.map((p) => p.volumeUsd)).toEqual([7, 0, 9]);
  });
});

describe('tipik gün profili', () => {
  const grid = completeHourGrid(
    hours(28, (d) => (d.getUTCHours() >= 14 && d.getUTCHours() < 17 ? 100 : d.getUTCHours() >= 2 && d.getUTCHours() < 5 ? 1 : 10)),
    now,
  );
  const profile = hourProfile(grid);

  it('en yoğun ve en sakin 3 saati bulur', () => {
    expect(dayWindow(profile, 'max')).toMatchObject({ startHour: 14, length: 3 });
    expect(dayWindow(profile, 'min')).toMatchObject({ startHour: 2, length: 3 });
    expect(profile.reduce((a, p) => a + p.share, 0)).toBeCloseTo(1);
    expect(profile[15]!.heat).toBe(1);
  });

  it('medyan kullanır: tek günlük sıçrama profili bozmaz', () => {
    const spiky = completeHourGrid(hours(28, (d) => (d.getUTCDate() === 20 && d.getUTCHours() === 3 ? 1e9 : 10)), now);
    expect(hourProfile(spiky)[3]!.medianVolumeUsd).toBe(10);
  });

  it('en yoğun pencereyi gece yarısından sararak bulur', () => {
    const night = hourProfile(completeHourGrid(hours(7, (d) => (d.getUTCHours() === 23 || d.getUTCHours() <= 1 ? 50 : 1)), now));
    expect(dayWindow(night, 'max').startHour).toBe(23);
  });

  it('haftalık matris 168 hücre üretir', () => {
    const m = weekMatrix(grid);
    expect(m).toHaveLength(168);
    expect(m.every((c) => c.samples === 4)).toBe(true);
  });
});

describe('şu an ve bugün', () => {
  const grid = completeHourGrid(hours(14, (d) => (d.getUTCHours() === 11 ? 100 : 10)), now);
  const profile = hourProfile(grid);

  it('son saati tipik değeriyle karşılaştırır', () => {
    const s = lastHourStatus(grid, profile)!;
    expect(s.hourStart).toBe('2026-09-28T11:00:00.000Z');
    expect(s.ratio).toBe(1);
    expect(s.level).toBe('aktif');
  });

  it('tipiğinin çok altında kalan yoğun saat bir kademe düşer', () => {
    const low = [...grid.slice(0, -1), { ...grid.at(-1)!, volumeUsd: 20 }];
    expect(lastHourStatus(low, profile)!.level).toBe('normal');
  });

  it('bugünün tamamlanan saatlerini döner', () => {
    const today = todaySeries(grid, now);
    expect(today.slice(0, 12).every((v) => v !== null)).toBe(true);
    expect(today.slice(12).every((v) => v === null)).toBe(true);
  });

  it('UTC dizisini yerel saate döndürür', () => {
    const utc = Array.from({ length: 24 }, (_, i) => i);
    expect(rotate(utc, 3)[3]).toBe(0);
    expect(rotate(utc, -5)[0]).toBe(5);
  });
});
