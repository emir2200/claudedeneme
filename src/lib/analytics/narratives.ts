// Narrative sınıflandırma ve momentum
//
// Sınıflandırma: token adı + sembolü üzerinde anahtar kelime eşleşmesi.
//  - ≥ 4 harfli anahtar kelimeler alt dize olarak aranır ("MEOWGPT" → cat + ai).
//  - Kısa anahtar kelimeler ("ai", "cz", "gm") yanlış pozitif üretmemek için yalnızca tam
//    kelime olarak ya da sembolün başında/sonunda eşleşir ("AIDOG" → ai, "RAIN" ✗).
// Bir token birden fazla narrative'e girebilir.

import type { NarrativeTrend } from '../types';
import { HOUR_MS, percentileRank, sum, weightedMean } from './stats';

export interface NarrativeDef {
  slug: string;
  name: string;
  keywords: string[];
}

export const NARRATIVES: NarrativeDef[] = [
  {
    slug: 'ai',
    name: 'AI Memes',
    keywords: ['ai', 'agi', 'gpt', 'agent', 'neural', 'llm', 'robot', 'bot', 'brain', 'cyber', 'synth', 'model'],
  },
  {
    slug: 'cat',
    name: 'Cat-Coins',
    keywords: ['cat', 'kitty', 'kitten', 'meow', 'neko', 'purr', 'mog', 'feline', 'catz'],
  },
  {
    slug: 'dog',
    name: 'Dog-Coins',
    keywords: ['dog', 'doge', 'inu', 'shib', 'pup', 'puppy', 'woof', 'shiba', 'hound'],
  },
  {
    slug: 'frog',
    name: 'Frog & Pepe',
    keywords: ['pepe', 'frog', 'toad', 'kek', 'ribbit'],
  },
  {
    slug: 'meta',
    name: 'Meta-Tickers',
    keywords: ['wagmi', 'ngmi', 'gm', 'cto', 'based', 'degen', 'ticker', 'meme', 'jeet', 'hodl', 'ape', 'moon', 'pump', 'send'],
  },
  {
    slug: 'political',
    name: 'PolitiFi',
    keywords: ['trump', 'maga', 'elon', 'doge', 'president', 'vote', 'senate', 'potus'],
  },
  {
    slug: 'cz',
    name: 'CZ & Binance Kültürü',
    keywords: ['cz', 'binance', 'bnb', 'safu', 'four', 'yzi', 'giggle'],
  },
  {
    slug: 'stocks',
    name: 'Hisse & Robinhood Memeleri',
    keywords: ['stock', 'stonk', 'hood', 'robin', 'wsb', 'gme', 'tsla', 'nvda', 'aapl', 'wallst', 'bull', 'bear'],
  },
];

export const NARRATIVE_BY_SLUG = new Map(NARRATIVES.map((n) => [n.slug, n]));

function words(text: string): string[] {
  return text.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
}

export function classifyNarratives(name: string, symbol: string): string[] {
  const nameWords = words(name);
  const sym = symbol.toLowerCase().replace(/[^a-z0-9]/g, '');
  const compact = [sym, ...nameWords].join(' ');
  const found: string[] = [];
  for (const def of NARRATIVES) {
    const hit = def.keywords.some((kw) => {
      if (kw.length >= 4) return compact.includes(kw);
      return (
        nameWords.includes(kw) ||
        sym === kw ||
        (sym.length > kw.length + 1 && (sym.startsWith(kw) || sym.endsWith(kw)))
      );
    });
    if (hit) found.push(def.slug);
  }
  return found;
}

// ─────────────────────────────────────────────────────────────────────────────
// Momentum
//
//   momentum = 100 × (0.35 × mention büyümesi + 0.25 × yeni token büyümesi
//                    + 0.25 × hacim payı + 0.15 × hacim ağırlıklı fiyat değişimi)
// Her bileşen narrative'ler arası persentile çevrilir. En az `minTokens` token'ı olan
// narrative'ler sıralamaya girer (tek token'lık "trendler" elenir).
// ─────────────────────────────────────────────────────────────────────────────

export const NARRATIVE_WEIGHTS = {
  mentionGrowth: 0.35,
  newTokenGrowth: 0.25,
  volumeShare: 0.25,
  priceChange: 0.15,
} as const;

export interface NarrativeTokenInput {
  symbol: string;
  narratives: string[];
  volume24hUsd: number;
  priceChange24hPct: number | null;
  poolCreatedAt: Date | null;
  mentions24h: number;
  mentionsPrev24h: number;
  /** Son 24 saatin saatlik mention serisi (eskiden yeniye, 24 eleman). */
  mentionSeries: number[];
}

export function computeNarrativeTrends(
  tokens: readonly NarrativeTokenInput[],
  now: Date,
  minTokens = 3,
): NarrativeTrend[] {
  const nowMs = now.getTime();
  const totalVolume = sum(tokens.map((t) => t.volume24hUsd));

  const rows = NARRATIVES.map((def) => {
    const members = tokens.filter((t) => t.narratives.includes(def.slug));
    const volume = sum(members.map((t) => t.volume24hUsd));
    const mentions = sum(members.map((t) => t.mentions24h));
    const mentionsPrev = sum(members.map((t) => t.mentionsPrev24h));
    const ages = members.map((t) => (t.poolCreatedAt ? nowMs - t.poolCreatedAt.getTime() : Infinity));
    const newTokens = ages.filter((a) => a <= 24 * HOUR_MS).length;
    const newTokensPrev = ages.filter((a) => a > 24 * HOUR_MS && a <= 48 * HOUR_MS).length;
    const priced = members.filter((t) => t.priceChange24hPct !== null);
    const vwChange =
      sum(priced.map((t) => t.volume24hUsd)) > 0
        ? sum(priced.map((t) => (t.priceChange24hPct ?? 0) * t.volume24hUsd)) /
          sum(priced.map((t) => t.volume24hUsd))
        : 0;
    const series = Array.from({ length: 24 }, (_, i) => sum(members.map((t) => t.mentionSeries[i] ?? 0)));
    const topSymbols = [...members]
      .sort((a, b) => b.volume24hUsd - a.volume24hUsd)
      .slice(0, 3)
      .map((t) => t.symbol);

    return {
      slug: def.slug,
      name: def.name,
      tokenCount: members.length,
      volume24hUsd: volume,
      volumeShare: totalVolume > 0 ? volume / totalVolume : 0,
      mentions24h: mentions,
      mentionGrowthPct: ((mentions + 1) / (mentionsPrev + 1) - 1) * 100,
      newTokens24h: newTokens,
      newTokenGrowth: (newTokens + 1) / (newTokensPrev + 1),
      avgPriceChangePct: vwChange,
      mentionSeries: series,
      topSymbols,
    };
  });

  const eligible = rows.filter((r) => r.tokenCount >= minTokens);
  const col = (pick: (r: (typeof rows)[number]) => number) => eligible.map(pick);
  const mentionGrowths = col((r) => r.mentionGrowthPct);
  const tokenGrowths = col((r) => r.newTokenGrowth);
  const shares = col((r) => r.volumeShare);
  const changes = col((r) => r.avgPriceChangePct);

  return eligible
    .map(({ newTokenGrowth, ...r }) => ({
      ...r,
      momentum: Math.round(
        100 *
          weightedMean([
            { value: percentileRank(r.mentionGrowthPct, mentionGrowths), weight: NARRATIVE_WEIGHTS.mentionGrowth },
            { value: percentileRank(newTokenGrowth, tokenGrowths), weight: NARRATIVE_WEIGHTS.newTokenGrowth },
            { value: percentileRank(r.volumeShare, shares), weight: NARRATIVE_WEIGHTS.volumeShare },
            { value: percentileRank(r.avgPriceChangePct, changes), weight: NARRATIVE_WEIGHTS.priceChange },
          ]),
      ),
    }))
    .sort((a, b) => b.momentum - a.momentum || b.mentionGrowthPct - a.mentionGrowthPct);
}
