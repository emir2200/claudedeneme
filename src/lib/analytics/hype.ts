// Günün Coin'i — sosyal hype × on-chain doğrulama
//
//   hypeScore = 100 × (0.35 × etkileşim + 0.25 × mention hızı
//                     + 0.20 × devir (Vol/MCap) + 0.20 × 24s fiyat momentumu)
//
// Her bileşen uygun adaylar arasında persentile çevrilir. Adaylık şartı: likidite ≥ $25K,
// piyasa değeri ≥ $100K (sosyal gürültünün çıkış yapmamış token'ları öne itmesini önler).
// Vol/MCap, wash-trade'i ödüllendirmemek için sıralamadan önce 5x'te kırpılır.
//
// Risk bayrakları sıralamayı değiştirmez, kullanıcıya gösterilir. Tek istisna: "asiri-devir"
// bayraklı token "Günün Coini" seçilemez (bkz. snapshot.ts).
//  - hype-likidite : $1K likidite başına etkileşim adayların üst %10'unda ve > 50
//                    (konuşulma, derinliği çok aşıyor → yüksek kayma/çıkış riski)
//  - asiri-devir   : Vol/MCap > 5 (olası wash-trade / bot hacmi)
//  - ince-likidite : Likidite / MCap < %5
//  - yeni-token    : 6 saatten genç havuz

import type { HypeToken, RiskFlag } from '../types';
import { HOUR_MS, percentileRank, weightedMean } from './stats';

export const HYPE_WEIGHTS = { engagement: 0.35, velocity: 0.25, turnover: 0.2, momentum: 0.2 } as const;

export interface HypeFilters {
  minLiquidityUsd: number;
  minMarketCapUsd: number;
}

export const DEFAULT_HYPE_FILTERS: HypeFilters = { minLiquidityUsd: 25_000, minMarketCapUsd: 100_000 };

export type HypeCandidate = Omit<
  HypeToken,
  'hypeScore' | 'riskFlags' | 'mentionVelocity' | 'volMcapRatio' | 'socialToLiquidity' | 'ageHours'
> & {
  mentionsPrev24h: number;
  poolCreatedAt: Date | null;
};

const TURNOVER_CAP = 5;

export function scoreHype(
  candidates: readonly HypeCandidate[],
  now: Date,
  filters: HypeFilters = DEFAULT_HYPE_FILTERS,
): HypeToken[] {
  const eligible = candidates.filter(
    (c) => c.liquidityUsd >= filters.minLiquidityUsd && c.marketCapUsd >= filters.minMarketCapUsd,
  );

  const derived = eligible.map((c) => {
    const { mentionsPrev24h, poolCreatedAt, ...rest } = c;
    return {
      ...rest,
      mentionVelocity: (c.mentions24h + 1) / (mentionsPrev24h + 1),
      volMcapRatio: c.marketCapUsd > 0 ? c.volume24hUsd / c.marketCapUsd : 0,
      socialToLiquidity: c.liquidityUsd > 0 ? c.engagements24h / (c.liquidityUsd / 1000) : 0,
      ageHours: poolCreatedAt ? (now.getTime() - poolCreatedAt.getTime()) / HOUR_MS : null,
    };
  });

  const engagements = derived.map((d) => d.engagements24h);
  const velocities = derived.map((d) => d.mentionVelocity);
  const turnovers = derived.map((d) => Math.min(d.volMcapRatio, TURNOVER_CAP));
  const momenta = derived.map((d) => d.priceChange24hPct ?? 0);
  const socialLiq = [...derived.map((d) => d.socialToLiquidity)].sort((a, b) => a - b);
  const socialLiqP90 = socialLiq.length ? socialLiq[Math.floor(socialLiq.length * 0.9)] ?? Infinity : Infinity;

  return derived
    .map((d) => {
      const riskFlags: RiskFlag[] = [];
      if (d.socialToLiquidity >= socialLiqP90 && d.socialToLiquidity > 50) riskFlags.push('hype-likidite');
      if (d.volMcapRatio > TURNOVER_CAP) riskFlags.push('asiri-devir');
      if (d.marketCapUsd > 0 && d.liquidityUsd / d.marketCapUsd < 0.05) riskFlags.push('ince-likidite');
      if (d.ageHours !== null && d.ageHours < 6) riskFlags.push('yeni-token');

      const hypeScore = Math.round(
        100 *
          weightedMean([
            { value: percentileRank(d.engagements24h, engagements), weight: HYPE_WEIGHTS.engagement },
            { value: percentileRank(d.mentionVelocity, velocities), weight: HYPE_WEIGHTS.velocity },
            {
              value: percentileRank(Math.min(d.volMcapRatio, TURNOVER_CAP), turnovers),
              weight: HYPE_WEIGHTS.turnover,
            },
            { value: percentileRank(d.priceChange24hPct ?? 0, momenta), weight: HYPE_WEIGHTS.momentum },
          ]),
      );
      return { ...d, hypeScore, riskFlags };
    })
    .sort((a, b) => b.hypeScore - a.hypeScore || b.engagements24h - a.engagements24h);
}

export const RISK_FLAG_TEXT: Record<RiskFlag, string> = {
  'hype-likidite': 'Konuşulma likiditeyi aşıyor',
  'asiri-devir': 'Aşırı devir (olası wash-trade)',
  'ince-likidite': 'İnce likidite',
  'yeni-token': '6 saatten genç',
};
