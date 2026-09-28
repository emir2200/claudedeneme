import { describe, expect, it } from 'vitest';
import {
  computeActivityIndex,
  dominanceScore,
  heatLabel,
  metricHeat,
  type ChainMetricSample,
} from '@/lib/analytics/activityIndex';

const sample = (v: number, tvl: number | null = 1000): ChainMetricSample => ({
  volume24hUsd: v * 24,
  volume1hUsd: v,
  txCount1h: v / 10,
  newPools1h: v / 100,
  tvlUsd: tvl,
});

const history = (from: number, to: number) =>
  Array.from({ length: to - from + 1 }, (_, i) => sample(from + i));

describe('metricHeat', () => {
  it('geçmişin tepesindeki değere ~1, dibindekine ~0 verir', () => {
    const h = history(1, 100);
    expect(metricHeat(sample(1000), h).volume1hUsd).toBe(1);
    expect(metricHeat(sample(0), h).volume1hUsd).toBe(0);
    expect(metricHeat(sample(50.5), h).volume1hUsd).toBeCloseTo(0.5, 2);
  });

  it('eksik metrik için null döner', () => {
    expect(metricHeat(sample(10, null), history(1, 10)).tvlUsd).toBeNull();
  });
});

describe('dominanceScore', () => {
  it('eşit pay 0.5, 2/3 ve üstü 1 olur', () => {
    expect(dominanceScore(1 / 3, 3)).toBeCloseTo(0.5);
    expect(dominanceScore(2 / 3, 3)).toBeCloseTo(1);
    expect(dominanceScore(0.9, 3)).toBe(1);
    expect(dominanceScore(0, 3)).toBe(0);
  });
});

describe('computeActivityIndex', () => {
  it('kendi geçmişine göre sıcak ve hacim lideri olan zincir en yüksek skoru alır', () => {
    const [hot, cold] = computeActivityIndex([
      { chain: 'solana', current: sample(500), history: history(1, 100) },
      { chain: 'bsc', current: sample(5), history: history(1, 100) },
    ]);
    expect(hot!.index).toBeGreaterThan(90);
    expect(cold!.index).toBeLessThan(10);
    expect(hot!.volumeShare + cold!.volumeShare).toBeCloseTo(1);
  });

  it('küçük ama olağanüstü aktif bir zincir, büyük ama durgun zinciri geçebilir', () => {
    const [big, small] = computeActivityIndex([
      // Büyük zincir: hacmi yüksek ama kendi geçmişinin dibinde
      { chain: 'solana', current: sample(1_000), history: history(1_000, 5_000) },
      // Küçük zincir: kendi geçmişinin tepesinde
      { chain: 'robinhood', current: sample(900), history: history(1, 100) },
    ]);
    // TVL her iki geçmişte de sabit → nötr (0.5) persentil, momentuma 0.10 × 0.5 katkı.
    expect(small!.momentum).toBeGreaterThan(0.9);
    expect(big!.momentum).toBeLessThan(0.1);
    expect(small!.index).toBeGreaterThan(big!.index);
  });

  it('0–100 aralığında kalır ve etiketler eşiklere uyar', () => {
    for (const r of computeActivityIndex([{ chain: 'bsc', current: sample(10), history: [] }])) {
      expect(r.index).toBeGreaterThanOrEqual(0);
      expect(r.index).toBeLessThanOrEqual(100);
    }
    expect(heatLabel(0)).toBe('Donuk');
    expect(heatLabel(59)).toBe('Ilık');
    expect(heatLabel(80)).toBe('Kızgın');
  });
});
