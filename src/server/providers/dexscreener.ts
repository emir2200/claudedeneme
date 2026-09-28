// DEXScreener — token başına havuz verisi (fiyat, mcap, likidite, hacim, işlem sayısı).
// Uç nokta: GET /tokens/v1/{chainId}/{adres1,adres2,...}  (istek başına en çok 30 adres,
// belgelenen sınır ~300 istek/dk). Anahtar gerekmez.

import { z } from 'zod';
import { getConfig } from '../config';
import { fetchJson, RateLimiter } from './http';

const num = z.number().nullish();
const window = z.object({ buys: z.number(), sells: z.number() }).nullish();

export const dexPairSchema = z.object({
  chainId: z.string(),
  dexId: z.string(),
  pairAddress: z.string(),
  baseToken: z.object({ address: z.string(), name: z.string(), symbol: z.string() }),
  quoteToken: z.object({ address: z.string(), symbol: z.string() }),
  priceNative: z.string().nullish(),
  priceUsd: z.string().nullish(),
  txns: z.object({ h1: window, h24: window }).partial().nullish(),
  volume: z.object({ h1: num, h24: num }).partial().nullish(),
  priceChange: z.object({ h1: num, h24: num }).partial().nullish(),
  liquidity: z.object({ usd: num }).partial().nullish(),
  fdv: num,
  marketCap: num,
  pairCreatedAt: num,
});
export type DexPair = z.infer<typeof dexPairSchema>;

export const DEXSCREENER_BATCH = 30;
const limiter = new RateLimiter(250);

export async function fetchTokenPairs(chainId: string, addresses: readonly string[]): Promise<DexPair[]> {
  if (addresses.length === 0) return [];
  if (addresses.length > DEXSCREENER_BATCH) throw new Error(`En çok ${DEXSCREENER_BATCH} adres gönderilebilir`);
  const base = getConfig().DEXSCREENER_BASE_URL;
  const url = `${base}/tokens/v1/${encodeURIComponent(chainId)}/${addresses.map(encodeURIComponent).join(',')}`;
  return fetchJson(url, { schema: z.array(dexPairSchema), limiter });
}

export interface TokenMarket {
  pairAddress: string;
  dexId: string;
  quoteAddress: string;
  priceUsd: number | null;
  priceNative: number | null;
  priceChange1hPct: number | null;
  priceChange24hPct: number | null;
  marketCapUsd: number | null;
  fdvUsd: number | null;
  /** Token'ın baz olduğu TÜM havuzların toplam likiditesi. */
  liquidityUsd: number;
  volume1hUsd: number;
  volume24hUsd: number;
  buys1h: number;
  sells1h: number;
  txCount24h: number;
  pairCreatedAt: Date | null;
}

const toNum = (s: string | null | undefined) => {
  const n = s == null ? NaN : Number(s);
  return Number.isFinite(n) ? n : null;
};

/**
 * Bir token'ın havuzlarını tek görüntüde birleştirir: fiyat ve mcap en likit havuzdan,
 * hacim/likidite/işlem sayısı token'ın baz olduğu tüm havuzların toplamından gelir.
 */
export function summarizeToken(pairs: readonly DexPair[], tokenAddress: string): TokenMarket | null {
  const target = tokenAddress.toLowerCase();
  const own = pairs.filter((p) => p.baseToken.address.toLowerCase() === target);
  if (own.length === 0) return null;
  const primary = own.reduce((best, p) => ((p.liquidity?.usd ?? 0) > (best.liquidity?.usd ?? 0) ? p : best));
  const total = (pick: (p: DexPair) => number | null | undefined) => own.reduce((a, p) => a + (pick(p) ?? 0), 0);

  return {
    pairAddress: primary.pairAddress,
    dexId: primary.dexId,
    quoteAddress: primary.quoteToken.address,
    priceUsd: toNum(primary.priceUsd),
    priceNative: toNum(primary.priceNative),
    priceChange1hPct: primary.priceChange?.h1 ?? null,
    priceChange24hPct: primary.priceChange?.h24 ?? null,
    marketCapUsd: primary.marketCap ?? null,
    fdvUsd: primary.fdv ?? null,
    liquidityUsd: total((p) => p.liquidity?.usd),
    volume1hUsd: total((p) => p.volume?.h1),
    volume24hUsd: total((p) => p.volume?.h24),
    buys1h: total((p) => p.txns?.h1?.buys),
    sells1h: total((p) => p.txns?.h1?.sells),
    txCount24h: total((p) => (p.txns?.h24 ? p.txns.h24.buys + p.txns.h24.sells : 0)),
    pairCreatedAt: primary.pairCreatedAt ? new Date(primary.pairCreatedAt) : null,
  };
}
