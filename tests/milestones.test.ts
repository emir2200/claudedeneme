import { describe, expect, it } from 'vitest';
import {
  advanceMilestone,
  qualifies,
  type MarketSample,
  type MilestoneState,
} from '@/lib/analytics/milestones';

const at = (min: number) => new Date(Date.UTC(2026, 8, 28, 12, min));
const s = (min: number, marketCapUsd: number | null, liquidityUsd: number | null, fdvUsd: number | null = null): MarketSample => ({
  at: at(min),
  marketCapUsd,
  fdvUsd,
  liquidityUsd,
});
const initial: MilestoneState = { streak: 0, pendingSince: null, crossedAt: null };

describe('qualifies', () => {
  it('mcap yolu asgari likidite ister', () => {
    expect(qualifies(s(0, 150_000, 20_000))).toBe(true);
    expect(qualifies(s(0, 150_000, 3_000))).toBe(false);
  });
  it('likidite tek başına eşiği aşabilir', () => {
    expect(qualifies(s(0, null, 120_000))).toBe(true);
  });
  it('mcap yoksa FDV kullanılır', () => {
    expect(qualifies(s(0, null, 15_000, 200_000))).toBe(true);
  });
});

describe('advanceMilestone', () => {
  it('iki ardışık örnekle onaylanır ve serinin ilk örneğine tarihlenir', () => {
    let st = advanceMilestone(initial, s(0, 120_000, 20_000));
    expect(st.crossedAt).toBeNull();
    expect(st.streak).toBe(1);
    st = advanceMilestone(st, s(5, 130_000, 20_000));
    expect(st.crossedAt).toEqual(at(0));
  });

  it('tek örneklik fitil sayılmaz ve seri sıfırlanır', () => {
    let st = advanceMilestone(initial, s(0, 120_000, 20_000));
    st = advanceMilestone(st, s(5, 90_000, 20_000));
    expect(st).toEqual(initial);
  });

  it('bir kez sayılan token tekrar sayılmaz (yapışkan)', () => {
    const crossed: MilestoneState = { streak: 2, pendingSince: at(0), crossedAt: at(0) };
    expect(advanceMilestone(crossed, s(10, 10_000, 1_000))).toBe(crossed);
  });
});
