import type { ChainId } from './chains';

// ─────────────────────────────────────────────────────────────────────────────
// Ham veri: snapshot üreticisinin girdisi. Canlı modda PostgreSQL'den
// (src/server/snapshot/loadFromDb.ts), demo modda simülatörden
// (src/server/simulation.ts) gelir. Böylece iki mod da AYNI analitik hattından geçer.
// ─────────────────────────────────────────────────────────────────────────────

export type DataMode = 'demo' | 'live';
export type Launchpad = 'PUMP_FUN' | 'FOUR_MEME' | 'OTHER';
export type TradeSide = 'BUY' | 'SELL';

/** VolumeByHour satırı. */
export interface RawHour {
  chain: ChainId;
  hourStart: Date;
  volumeUsd: number;
  txCount: number;
  buyCount: number;
  sellCount: number;
  botTxCount: number;
  humanTxCount: number;
  volatilityPct: number;
  newPools: number;
}

/** ChainStats satırı. */
export interface RawChainStat {
  chain: ChainId;
  hourStart: Date;
  volume1hUsd: number;
  volume24hUsd: number;
  txCount1h: number;
  txCount24h: number;
  newPools1h: number;
  newPools24h: number;
  tvlUsd: number | null;
}

/** LaunchDaily satırı. `day` UTC `YYYY-MM-DD`. */
export interface RawLaunchDay {
  chain: ChainId;
  day: string;
  crossed100k: number;
  newTokens: number;
  byLaunchpad: Partial<Record<Launchpad, number>>;
}

export interface RawToken {
  chain: ChainId;
  address: string;
  symbol: string;
  name: string;
  launchpad: Launchpad;
  narratives: string[];
  poolCreatedAt: Date | null;
  priceUsd: number | null;
  priceChange1hPct: number | null;
  priceChange24hPct: number | null;
  marketCapUsd: number | null;
  liquidityUsd: number | null;
  volume24hUsd: number | null;
  txCount24h: number | null;
  milestone100kAt: Date | null;
}

/** Token başına saatlik sosyal toplam (tüm kaynaklar birleşik). */
export interface RawSocialHour {
  chain: ChainId;
  address: string;
  hourStart: Date;
  mentions: number;
  engagements: number;
  uniqueAuthors: number;
  sentiment: number | null;
}

export interface RawWhale {
  id: string;
  chain: ChainId;
  tokenAddress: string;
  tokenSymbol: string | null;
  wallet: string;
  walletLabel: string | null;
  isSmartMoney: boolean;
  side: TradeSide;
  usdValue: number;
  txHash: string;
  blockTime: Date;
}

export interface RawDashboardData {
  now: Date;
  mode: DataMode;
  /** Son ~5 haftalık VolumeByHour (24x7 matris için 4 tam hafta + tampon). */
  hours: RawHour[];
  /** Son ~8 günlük ChainStats (7 günlük persentil penceresi + 24 saatlik index geçmişi). */
  chainStats: RawChainStat[];
  /** Son 30 günlük LaunchDaily. */
  launches: RawLaunchDay[];
  tokens: RawToken[];
  /** Son 48 saatlik sosyal metrikler. */
  social: RawSocialHour[];
  /** Son 24 saatlik balina swapları. */
  whales: RawWhale[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Snapshot: /api/dashboard yanıtı. JSON'a serileşebilir (tarihler ISO string).
// ─────────────────────────────────────────────────────────────────────────────

export const ACTIVITY_METRICS = [
  'volume24hUsd',
  'volume1hUsd',
  'txCount1h',
  'newPools1h',
  'tvlUsd',
] as const;
export type ActivityMetric = (typeof ACTIVITY_METRICS)[number];

export type HeatLabel = 'Donuk' | 'Soğuk' | 'Ilık' | 'Sıcak' | 'Kızgın';

export interface ChainActivity {
  chain: ChainId;
  /** 0–100 */
  activityIndex: number;
  label: HeatLabel;
  /** 0–1: metriklerin kendi 7 günlük geçmişine göre ağırlıklı persentili. */
  momentum: number;
  /** 0–1: zincirin 1s hacim payından türetilen baskınlık skoru. */
  dominance: number;
  /** 0–1: 1s hacmin üç zincir içindeki payı. */
  volumeShare: number;
  metrics: Record<ActivityMetric, number | null>;
  /** 0–1: her metriğin kendi 7 günlük geçmişindeki persentili (ısı hücresi rengi). */
  heat: Record<ActivityMetric, number | null>;
  /** Son 24 saatin saatlik Activity Index değerleri (eskiden yeniye). */
  indexHistory: number[];
}

export interface LaunchDayPoint {
  date: string;
  solana: number;
  bsc: number;
  robinhood: number;
}

export interface LaunchToday {
  count: number;
  yesterday: number;
  /** Son 7 tam günün ortalaması. */
  avg7d: number;
  /** En çok mezun veren launchpad ve payı (0–1). */
  topLaunchpad: { launchpad: Launchpad; share: number } | null;
}

export interface LaunchReport {
  /** Son 30 gün, eskiden yeniye; son eleman bugün (henüz bitmedi). */
  days: LaunchDayPoint[];
  today: Record<ChainId, LaunchToday>;
  /** Bugünün (UTC) geçen kısmı, 0–1. */
  dayProgress: number;
  thresholdUsd: number;
}

export type MatrixKey = ChainId | 'all';

export interface MatrixCell {
  /** 0–1 göreli sıcaklık. */
  heat: number;
  /** Hücredeki haftaların medyan saatlik hacmi. */
  volumeUsd: number;
  txCount: number;
  /** İnsan işlemi payı (0–1); veri yoksa null. */
  humanShare: number | null;
  volatilityPct: number;
  samples: number;
}

export type TradeLevel = 'aktif' | 'normal' | 'sakin';

export interface TradeWindowReport {
  /** Hafta sayısı (medyan penceresi). */
  weeks: number;
  /**
   * 168 hücrelik düz dizi, UTC. index = gün * 24 + saat; gün 0 = Pazartesi.
   * İstemci yerel saate çevirmek için diziyi döndürür (bkz. rotateMatrix).
   */
  matrices: Record<MatrixKey, MatrixCell[]>;
  /** Şu anki haftanın-saati: tarihsel sıcaklık + canlı saat hacminin hücre medyanına oranı. */
  now: Record<MatrixKey, { heat: number; level: TradeLevel; liveRatio: number | null }>;
  /** Son 4 saatin en yüksek hacimli saati. */
  recent: Record<MatrixKey, { hourStart: string; volumeUsd: number; txCount: number } | null>;
  /** Haftanın en sıcak 3 saatlik penceresi (UTC). */
  best: Record<MatrixKey, { dow: number; startHour: number; length: number; avgHeat: number }>;
}

export interface NarrativeTrend {
  slug: string;
  name: string;
  tokenCount: number;
  volume24hUsd: number;
  volumeShare: number;
  mentions24h: number;
  /** Önceki 24 saate göre mention değişimi (%). */
  mentionGrowthPct: number;
  newTokens24h: number;
  /** Hacim ağırlıklı 24s fiyat değişimi (%). */
  avgPriceChangePct: number;
  /** 0–100 */
  momentum: number;
  /** Son 24 saatin saatlik mention serisi. */
  mentionSeries: number[];
  topSymbols: string[];
}

export type RiskFlag = 'hype-likidite' | 'asiri-devir' | 'ince-likidite' | 'yeni-token';

export interface HypeToken {
  chain: ChainId;
  address: string;
  symbol: string;
  name: string;
  narratives: string[];
  launchpad: Launchpad;
  priceUsd: number | null;
  priceChange24hPct: number | null;
  marketCapUsd: number;
  liquidityUsd: number;
  volume24hUsd: number;
  mentions24h: number;
  engagements24h: number;
  /** (mention 24s + 1) / (önceki 24s + 1) */
  mentionVelocity: number;
  volMcapRatio: number;
  /** $1K likidite başına etkileşim. */
  socialToLiquidity: number;
  sentiment: number | null;
  /** 0–100 */
  hypeScore: number;
  riskFlags: RiskFlag[];
  mentionSeries: number[];
  ageHours: number | null;
}

export interface WhaleTradeView {
  id: string;
  chain: ChainId;
  tokenAddress: string;
  tokenSymbol: string | null;
  wallet: string;
  walletLabel: string | null;
  isSmartMoney: boolean;
  side: TradeSide;
  usdValue: number;
  txHash: string;
  blockTime: string;
}

export interface WhaleReport {
  trades: WhaleTradeView[];
  /** Son 1 saatin balina alım/satım toplamları. */
  netFlow1h: Record<ChainId, { buyUsd: number; sellUsd: number; count: number }>;
  minUsd: number;
}

export interface TickerItem {
  chain: ChainId;
  symbol: string;
  priceChange24hPct: number;
  volume24hUsd: number;
}

export interface DashboardSnapshot {
  generatedAt: string;
  mode: DataMode;
  chains: ChainActivity[];
  launches: LaunchReport;
  trade: TradeWindowReport;
  narratives: NarrativeTrend[];
  risingNarrative: NarrativeTrend | null;
  coinOfTheDay: HypeToken | null;
  hypeLeaders: HypeToken[];
  whales: WhaleReport;
  ticker: TickerItem[];
}
