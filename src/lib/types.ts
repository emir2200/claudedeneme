// API yanıt tipleri. JSON'a serileşebilir (tarihler ISO string).

export const PERIODS = ['day', 'week', 'month'] as const;
export type Period = (typeof PERIODS)[number];

export interface PeriodStat {
  /** Dönemin toplam DEX hacmi (USD). */
  volumeUsd: number;
  /** Bir önceki eşit uzunluktaki dönemin hacmi; veri yoksa null. */
  prevVolumeUsd: number | null;
  /** Önceki döneme göre değişim (%); hesaplanamıyorsa null. */
  changePct: number | null;
  /** Sıralamadaki chain'lerin toplam hacmi içindeki pay (0–1). */
  share: number;
  /** 1 = en aktif. */
  rank: number;
}

export interface ChainRanking {
  chain: string;
  name: string;
  stats: Record<Period, PeriodStat>;
  /** Son 30 tam günün günlük hacmi (eskiden yeniye), eğri için. */
  last30: number[];
}

export interface RankingsReport {
  generatedAt: string;
  /** Sıralamanın dayandığı son tam gün (UTC, YYYY-MM-DD). */
  asOfDay: string | null;
  rows: ChainRanking[];
  /** Verisi alınamayan chain'ler. */
  missing: Array<{ chain: string; name: string; reason: string }>;
  /** Önbellekteki eski veri sunuluyorsa true (kaynak şu an yanıt vermiyor). */
  stale: boolean;
}

export interface HourProfilePoint {
  /** UTC saat (0–23). */
  hour: number;
  /** Bu saatin günlük medyan hacmi (USD). */
  medianVolumeUsd: number;
  /** Tipik bir günün hacmi içindeki payı (0–1). */
  share: number;
  /** 24 saat içinde göreli sıcaklık (0–1). */
  heat: number;
}

export interface MatrixCell {
  heat: number;
  volumeUsd: number;
  samples: number;
}

export type ActivityLevel = 'aktif' | 'normal' | 'sakin';

export interface HoursReport {
  chain: string;
  name: string;
  generatedAt: string;
  /** Hesaba katılan havuzlar (en yüksek 24s hacimli). */
  pools: Array<{ name: string; volume24hUsd: number | null }>;
  /** Kapsanan tam gün sayısı. */
  daysCovered: number;
  /** 24 saatlik tipik gün profili (UTC). */
  profile: HourProfilePoint[];
  /** 7 × 24 haftalık matris (UTC, index = gün × 24 + saat, gün 0 = Pazartesi). */
  matrix: MatrixCell[];
  /** Tipik günün en yoğun 3 saatlik penceresi (UTC başlangıç saati). */
  bestWindow: { startHour: number; length: number; share: number };
  /** Tipik günün en sakin 3 saatlik penceresi. */
  quietWindow: { startHour: number; length: number; share: number };
  /** Son tamamlanan saat ve o saatin tipik değeriyle karşılaştırması. */
  lastHour: { hourStart: string; volumeUsd: number; typicalUsd: number; ratio: number | null; level: ActivityLevel } | null;
  /** Bugünün (UTC) saatlik hacmi; henüz gelmemiş saatler null. */
  today: Array<number | null>;
  stale: boolean;
}

export interface ApiError {
  error: string;
}
