// DefiLlama — zincir TVL'i ve zincir geneli DEX hacmi (bağlam metrikleri).
// Uç noktalar: GET /v2/chains, GET /overview/dexs/{chain}. Anahtar gerekmez.

import { z } from 'zod';
import { getConfig } from '../config';
import { fetchJson, RateLimiter } from './http';

const limiter = new RateLimiter(30);

export async function fetchChainTvls(): Promise<Map<string, number>> {
  const base = getConfig().DEFILLAMA_BASE_URL;
  const rows = await fetchJson(`${base}/v2/chains`, {
    schema: z.array(z.object({ name: z.string(), tvl: z.number().nullish() })),
    limiter,
  });
  return new Map(rows.flatMap((r) => (r.tvl == null ? [] : [[r.name.toLowerCase(), r.tvl] as const])));
}

export async function fetchChainDexVolume24h(chainName: string): Promise<number | null> {
  const base = getConfig().DEFILLAMA_BASE_URL;
  const url = `${base}/overview/dexs/${encodeURIComponent(chainName)}?excludeTotalDataChart=true&excludeTotalDataChartBreakdown=true`;
  const res = await fetchJson(url, { schema: z.object({ total24h: z.number().nullish() }), limiter });
  return res.total24h ?? null;
}
