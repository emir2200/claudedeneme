import { describe, expect, it } from 'vitest';
import { classifyNarratives, computeNarrativeTrends, type NarrativeTokenInput } from '@/lib/analytics/narratives';

describe('classifyNarratives', () => {
  it('bileşik sembolleri birden çok narrative olarak etiketler', () => {
    expect(classifyNarratives('Meow GPT', 'MEOWGPT')).toEqual(expect.arrayContaining(['ai', 'cat']));
  });

  it('kısa anahtar kelimeleri yalnızca kelime/sembol sınırında eşler', () => {
    expect(classifyNarratives('AI Dog', 'AIDOG')).toEqual(expect.arrayContaining(['ai', 'dog']));
    expect(classifyNarratives('Rain Maker', 'RAIN')).not.toContain('ai');
    expect(classifyNarratives('Chain Pal', 'CHAINPAL')).not.toContain('ai');
  });

  it('eşleşme yoksa boş dizi döner', () => {
    expect(classifyNarratives('Blue Whale', 'BLUW')).toEqual([]);
  });
});

describe('computeNarrativeTrends', () => {
  const now = new Date('2026-09-28T12:00:00Z');
  const hoursAgo = (h: number) => new Date(now.getTime() - h * 3_600_000);
  const tok = (narr: string, over: Partial<NarrativeTokenInput> = {}): NarrativeTokenInput => ({
    symbol: narr.toUpperCase(),
    narratives: [narr],
    volume24hUsd: 1_000,
    priceChange24hPct: 0,
    poolCreatedAt: hoursAgo(100),
    mentions24h: 100,
    mentionsPrev24h: 100,
    mentionSeries: new Array(24).fill(4),
    ...over,
  });

  it('mention ve yeni token büyümesi yüksek narrative ilk sırada olur', () => {
    const tokens = [
      ...Array.from({ length: 4 }, () => tok('ai', { mentions24h: 500, mentionsPrev24h: 100, poolCreatedAt: hoursAgo(5), volume24hUsd: 5_000, priceChange24hPct: 80 })),
      ...Array.from({ length: 4 }, () => tok('cat')),
      ...Array.from({ length: 4 }, () => tok('dog', { mentions24h: 50, mentionsPrev24h: 200 })),
    ];
    const trends = computeNarrativeTrends(tokens, now);
    expect(trends[0]!.slug).toBe('ai');
    expect(trends[0]!.mentionGrowthPct).toBeGreaterThan(300);
    expect(trends[0]!.newTokens24h).toBe(4);
    expect(trends.at(-1)!.slug).toBe('dog');
  });

  it('asgari token sayısının altındaki narrative sıralamaya girmez', () => {
    const trends = computeNarrativeTrends([tok('frog'), tok('ai'), tok('ai'), tok('ai')], now);
    expect(trends.map((t) => t.slug)).toEqual(['ai']);
  });
});
