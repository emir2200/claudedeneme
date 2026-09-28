// 100K+ çıkış tespiti
//
// Bir token, piyasa değeri (yoksa FDV) VEYA likiditesi eşiği (varsayılan $100K)
// ART ARDA `confirmSamples` örnekte (varsayılan 2 × 5 dk) aştığında "çıkış yaptı" sayılır.
// - Tek örneklik fitiller ve anlık fiyat manipülasyonları elenir.
// - Piyasa değeri yolu için asgari likidite şartı vardır: $3K likiditeyle "100K mcap"
//   gösteren token'lar (arzı kilitli, fiyatı şişirilmiş) sayılmaz.
// - Çıkış zamanı, onaylanan serinin İLK örneğidir; gün ataması buna göre yapılır.
// - Her token ömründe yalnızca bir kez sayılır (yapışkan).
// Yöntem launchpad'den bağımsızdır: Pump.fun, Four.meme veya doğrudan DEX'te açılan
// havuzlar aynı kuralla ölçülür.

export interface MilestoneConfig {
  thresholdUsd: number;
  confirmSamples: number;
  minLiquidityForMcapUsd: number;
}

export const DEFAULT_MILESTONE_CONFIG: MilestoneConfig = {
  thresholdUsd: 100_000,
  confirmSamples: 2,
  minLiquidityForMcapUsd: 10_000,
};

export interface MilestoneState {
  streak: number;
  pendingSince: Date | null;
  crossedAt: Date | null;
}

export interface MarketSample {
  at: Date;
  marketCapUsd: number | null;
  fdvUsd: number | null;
  liquidityUsd: number | null;
}

export function qualifies(sample: MarketSample, cfg: MilestoneConfig = DEFAULT_MILESTONE_CONFIG): boolean {
  const liquidity = sample.liquidityUsd ?? 0;
  const cap = sample.marketCapUsd ?? sample.fdvUsd ?? 0;
  const byCap = cap >= cfg.thresholdUsd && liquidity >= cfg.minLiquidityForMcapUsd;
  const byLiquidity = liquidity >= cfg.thresholdUsd;
  return byCap || byLiquidity;
}

/** Bir sonraki örnekle durumu ilerletir. Saf fonksiyon; worker sonucu Token satırına yazar. */
export function advanceMilestone(
  state: MilestoneState,
  sample: MarketSample,
  cfg: MilestoneConfig = DEFAULT_MILESTONE_CONFIG,
): MilestoneState {
  if (state.crossedAt) return state;
  if (!qualifies(sample, cfg)) return { streak: 0, pendingSince: null, crossedAt: null };

  const streak = state.streak + 1;
  const pendingSince = state.pendingSince ?? sample.at;
  if (streak >= cfg.confirmSamples) return { streak, pendingSince, crossedAt: pendingSince };
  return { streak, pendingSince, crossedAt: null };
}
