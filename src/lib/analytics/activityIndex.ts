// Zincir Activity Index (0–100)
//
//   index = 100 × (0.65 × Momentum + 0.35 × Baskınlık)
//
// Momentum  — Her metriğin şu anki değerinin, zincirin KENDİ son 7 günlük saatlik
//             geçmişindeki persentili; ağırlıklı ortalama. "Bu zincir her zamankinden
//             sıcak mı?" sorusunu yanıtlar ve Solana'nın doğal hacim üstünlüğünü nötrler.
// Baskınlık — 1s hacim payı × zincir sayısı / 2 (0–1'e kırpılır). Eşit pay (1/3) → 0.5,
//             hacmin ≥ 2/3'ü tek zincirdeyse → 1. "Para şu an nerede?" sorusunu yanıtlar.

import type { ChainId } from '../chains';
import { ACTIVITY_METRICS, type ActivityMetric, type HeatLabel } from '../types';
import { clamp, percentileRank, weightedMean } from './stats';

export type ChainMetricSample = Record<ActivityMetric, number | null>;

export const ACTIVITY_WEIGHTS: Record<ActivityMetric, number> = {
  volume1hUsd: 0.3,
  txCount1h: 0.25,
  newPools1h: 0.2,
  volume24hUsd: 0.15,
  tvlUsd: 0.1,
};

export const MOMENTUM_WEIGHT = 0.65;
export const DOMINANCE_WEIGHT = 0.35;

export interface ActivityInput {
  chain: ChainId;
  current: ChainMetricSample;
  /** Aynı zincirin önceki saatlik örnekleri (tipik olarak son 168 saat). */
  history: ChainMetricSample[];
}

export interface ActivityResult {
  chain: ChainId;
  index: number;
  label: HeatLabel;
  momentum: number;
  dominance: number;
  volumeShare: number;
  heat: Record<ActivityMetric, number | null>;
}

/** Her metriğin geçmişe göre persentili; değer yoksa null. */
export function metricHeat(
  current: ChainMetricSample,
  history: readonly ChainMetricSample[],
): Record<ActivityMetric, number | null> {
  const heat = {} as Record<ActivityMetric, number | null>;
  for (const metric of ACTIVITY_METRICS) {
    const value = current[metric];
    if (value === null || !Number.isFinite(value)) {
      heat[metric] = null;
      continue;
    }
    const sample: number[] = [];
    for (const h of history) {
      const v = h[metric];
      if (v !== null && Number.isFinite(v)) sample.push(v);
    }
    heat[metric] = percentileRank(value, sample);
  }
  return heat;
}

export function dominanceScore(volumeShare: number, chainCount: number): number {
  return clamp((volumeShare * chainCount) / 2);
}

export function heatLabel(index: number): HeatLabel {
  if (index < 20) return 'Donuk';
  if (index < 40) return 'Soğuk';
  if (index < 60) return 'Ilık';
  if (index < 80) return 'Sıcak';
  return 'Kızgın';
}

export function computeActivityIndex(inputs: readonly ActivityInput[]): ActivityResult[] {
  const n = inputs.length;
  const totalVolume = inputs.reduce((acc, i) => acc + Math.max(0, i.current.volume1hUsd ?? 0), 0);

  return inputs.map((input) => {
    const volume = Math.max(0, input.current.volume1hUsd ?? 0);
    const volumeShare = totalVolume > 0 ? volume / totalVolume : 1 / Math.max(1, n);
    const heat = metricHeat(input.current, input.history);
    const momentum = weightedMean(
      ACTIVITY_METRICS.map((m) => ({ value: heat[m], weight: ACTIVITY_WEIGHTS[m] })),
    );
    const dominance = dominanceScore(volumeShare, n);
    const index = Math.round(100 * (MOMENTUM_WEIGHT * momentum + DOMINANCE_WEIGHT * dominance));
    return {
      chain: input.chain,
      index,
      label: heatLabel(index),
      momentum,
      dominance,
      volumeShare,
      heat,
    };
  });
}
