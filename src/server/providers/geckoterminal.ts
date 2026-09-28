// GeckoTerminal — bir ağdaki en yüksek hacimli havuzlar ve saatlik OHLCV.
// Uç noktalar:
//   GET /networks/{network}/pools?page=1&sort=h24_volume_usd_desc
//   GET /networks/{network}/pools/{havuz}/ohlcv/hour?aggregate=1&limit=N&currency=usd
//     → data.attributes.ohlcv_list = [[unixSaniye, açılış, yüksek, düşük, kapanış, hacimUsd], …]
// Ücretsiz katman dakikada ~30 istek; anahtar gerekmez.

import { z } from 'zod';
import type { HourlyPoint } from '@/lib/analytics/hours';
import { baseUrls } from '../config';
import { fetchJson, RateLimiter } from './http';

const HEADERS = { accept: 'application/json;version=20230302' };
const limiter = new RateLimiter(25);

export const poolsSchema = z.object({
  data: z.array(
    z.object({
      attributes: z.object({
        address: z.string(),
        name: z.string(),
        volume_usd: z.object({ h24: z.string().nullish() }).partial().nullish(),
      }),
    }),
  ),
});

export const ohlcvSchema = z.object({
  data: z.object({
    attributes: z.object({ ohlcv_list: z.array(z.array(z.number())) }),
  }),
});

export interface TopPool {
  address: string;
  name: string;
  volume24hUsd: number | null;
}

export function parsePools(res: z.infer<typeof poolsSchema>): TopPool[] {
  return res.data
    .map((p) => {
      const v = Number(p.attributes.volume_usd?.h24);
      return { address: p.attributes.address, name: p.attributes.name, volume24hUsd: Number.isFinite(v) ? v : null };
    })
    .sort((a, b) => (b.volume24hUsd ?? 0) - (a.volume24hUsd ?? 0));
}

export function parseOhlcv(res: z.infer<typeof ohlcvSchema>): HourlyPoint[] {
  return res.data.attributes.ohlcv_list
    .filter((row) => row.length >= 6 && Number.isFinite(row[0]) && Number.isFinite(row[5]))
    .map((row) => ({ hourStart: row[0]! * 1000, volumeUsd: row[5]! }));
}

export async function fetchTopPools(network: string, count: number): Promise<TopPool[]> {
  const url = `${baseUrls().geckoterminal}/networks/${encodeURIComponent(network)}/pools?page=1&sort=h24_volume_usd_desc`;
  const res = await fetchJson(url, { schema: poolsSchema, limiter, headers: HEADERS, retries: 2 });
  return parsePools(res).slice(0, count);
}

export async function fetchHourlyVolume(network: string, pool: string, limit: number): Promise<HourlyPoint[]> {
  const url = `${baseUrls().geckoterminal}/networks/${encodeURIComponent(network)}/pools/${encodeURIComponent(pool)}/ohlcv/hour?aggregate=1&limit=${limit}&currency=usd`;
  return parseOhlcv(await fetchJson(url, { schema: ohlcvSchema, limiter, headers: HEADERS, retries: 2 }));
}
