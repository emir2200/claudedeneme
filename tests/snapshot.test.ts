import { describe, expect, it } from 'vitest';
import { CHAIN_IDS } from '@/lib/chains';
import { buildSnapshot } from '@/lib/analytics/snapshot';
import { simulateRawData } from '@/server/simulation';

const now = new Date('2026-09-28T14:37:00Z');

describe('simülatör + snapshot hattı', () => {
  const raw = simulateRawData(now);
  const snap = buildSnapshot(raw);

  it('deterministiktir', () => {
    expect(buildSnapshot(simulateRawData(now))).toEqual(snap);
  });

  it('her zincir için geçerli bir Activity Index üretir', () => {
    expect(snap.chains.map((c) => c.chain)).toEqual([...CHAIN_IDS]);
    for (const c of snap.chains) {
      expect(c.activityIndex).toBeGreaterThanOrEqual(0);
      expect(c.activityIndex).toBeLessThanOrEqual(100);
      expect(c.indexHistory).toHaveLength(24);
      expect(c.indexHistory.at(-1)).toBe(c.activityIndex);
    }
    expect(snap.chains.reduce((a, c) => a + c.volumeShare, 0)).toBeCloseTo(1);
  });

  it('30 günlük çıkış serisi ve bugünün sayacı tutarlıdır', () => {
    expect(snap.launches.days).toHaveLength(30);
    expect(snap.launches.days.at(-1)!.date).toBe('2026-09-28');
    expect(snap.launches.today.solana.count).toBe(snap.launches.days.at(-1)!.solana);
    expect(snap.launches.dayProgress).toBeCloseTo((14 * 60 + 37) / 1440, 5);
  });

  it('tüm matrisler 168 hücre ve 0–1 sıcaklık içerir', () => {
    for (const key of [...CHAIN_IDS, 'all'] as const) {
      const cells = snap.trade.matrices[key];
      expect(cells).toHaveLength(168);
      expect(cells.every((c) => c.heat >= 0 && c.heat <= 1 && c.samples === 4)).toBe(true);
      expect(snap.trade.recent[key]).not.toBeNull();
    }
  });

  it('günün coini, narrative ve balina çıktıları dolu', () => {
    expect(snap.coinOfTheDay).not.toBeNull();
    const clean = snap.hypeLeaders.filter((h) => !h.riskFlags.includes('asiri-devir'));
    expect(snap.coinOfTheDay!.riskFlags).not.toContain('asiri-devir');
    expect(snap.coinOfTheDay!.hypeScore).toBe(Math.max(...clean.map((h) => h.hypeScore)));
    expect(snap.risingNarrative?.slug).toBe(snap.narratives[0]!.slug);
    expect(snap.whales.trades.length).toBeGreaterThan(0);
    expect(snap.whales.trades.every((t) => t.usdValue >= snap.whales.minUsd)).toBe(true);
    expect(snap.ticker.length).toBeGreaterThan(0);
  });

  it('JSON’a kayıpsız serileşir', () => {
    expect(JSON.parse(JSON.stringify(snap))).toEqual(snap);
  });
});
