// LunarCrush v4 — konu (cashtag) bazında saatlik sosyal zaman serisi.
// Uç nokta: GET /api4/public/topic/{topic}/time-series/v1?bucket=hour&interval=1w
// Kimlik doğrulama: "Authorization: Bearer <API_KEY>". LunarCrush X, Reddit, YouTube,
// TikTok ve haberleri birleştirdiği için kaynak "AGGREGATED" olarak kaydedilir.
// Not: Alan adları belgelere göre yazıldı; canlı yanıtla doğrulanmadı. Şema gevşek
// tutuldu ve eksik alanlar 0/null kabul edilir.

import { z } from 'zod';
import { fetchJson, RateLimiter } from './http';

const pointSchema = z.object({
  time: z.number(),
  posts_created: z.number().nullish(),
  interactions: z.number().nullish(),
  contributors_active: z.number().nullish(),
  /** Olumlu gönderi yüzdesi (0–100). */
  sentiment: z.number().nullish(),
});

const responseSchema = z.object({ data: z.array(pointSchema) });

export interface SocialPoint {
  hourStart: Date;
  mentions: number;
  engagements: number;
  uniqueAuthors: number;
  sentiment: number | null;
}

const limiter = new RateLimiter(10);

export function cashtag(symbol: string): string {
  return `$${symbol.toLowerCase()}`;
}

export async function fetchTopicHourly(topic: string, apiKey: string): Promise<SocialPoint[]> {
  const url = `https://lunarcrush.com/api4/public/topic/${encodeURIComponent(topic)}/time-series/v1?bucket=hour&interval=1w`;
  const res = await fetchJson(url, { schema: responseSchema, limiter, headers: { authorization: `Bearer ${apiKey}` } });
  return res.data.map((p) => ({
    hourStart: new Date(Math.floor(p.time / 3600) * 3600 * 1000),
    mentions: p.posts_created ?? 0,
    engagements: p.interactions ?? 0,
    uniqueAuthors: p.contributors_active ?? 0,
    sentiment: p.sentiment == null ? null : p.sentiment / 100,
  }));
}
