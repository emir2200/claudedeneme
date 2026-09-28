// GeckoTerminal — yeni havuz keşfi.
// Uç nokta: GET /networks/{network}/new_pools?page=N&include=base_token (JSON:API biçimi).
// Ücretsiz katman ~30 istek/dk. Anahtar gerekmez.

import { z } from 'zod';
import { getConfig } from '../config';
import { fetchJson, RateLimiter } from './http';

const poolSchema = z.object({
  id: z.string(),
  attributes: z.object({
    address: z.string(),
    name: z.string(),
    pool_created_at: z.string().nullish(),
    reserve_in_usd: z.string().nullish(),
  }),
  relationships: z.object({
    base_token: z.object({ data: z.object({ id: z.string() }) }),
    dex: z.object({ data: z.object({ id: z.string() }) }).nullish(),
  }),
});

const includedSchema = z.object({
  id: z.string(),
  type: z.string(),
  attributes: z.object({ address: z.string(), name: z.string(), symbol: z.string() }).partial(),
});

const responseSchema = z.object({
  data: z.array(poolSchema),
  included: z.array(includedSchema).nullish(),
});

export interface DiscoveredPool {
  poolAddress: string;
  tokenAddress: string;
  name: string;
  symbol: string;
  dexId: string | null;
  poolCreatedAt: Date | null;
}

const limiter = new RateLimiter(25);

export async function fetchNewPools(network: string, page = 1): Promise<DiscoveredPool[]> {
  const base = getConfig().GECKOTERMINAL_BASE_URL;
  const url = `${base}/networks/${encodeURIComponent(network)}/new_pools?page=${page}&include=base_token`;
  const res = await fetchJson(url, {
    schema: responseSchema,
    limiter,
    headers: { accept: 'application/json;version=20230302' },
  });
  return parseNewPools(res, network);
}

export function parseNewPools(res: z.infer<typeof responseSchema>, network: string): DiscoveredPool[] {
  const tokens = new Map((res.included ?? []).filter((i) => i.type === 'token').map((i) => [i.id, i.attributes]));
  return res.data.flatMap((pool) => {
    const tokenId = pool.relationships.base_token.data.id;
    const token = tokens.get(tokenId);
    // Kimlik biçimi "<network>_<adres>".
    const tokenAddress = token?.address ?? tokenId.slice(network.length + 1);
    if (!tokenAddress) return [];
    const [poolBase] = pool.attributes.name.split(' / ');
    return [
      {
        poolAddress: pool.attributes.address,
        tokenAddress,
        name: token?.name ?? poolBase ?? tokenAddress,
        symbol: token?.symbol ?? poolBase ?? '?',
        dexId: pool.relationships.dex?.data.id ?? null,
        poolCreatedAt: pool.attributes.pool_created_at ? new Date(pool.attributes.pool_created_at) : null,
      },
    ];
  });
}
