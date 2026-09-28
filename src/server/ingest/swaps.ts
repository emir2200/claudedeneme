// Swap olaylarının ortak kayıt yolu (Helius webhook'u ve EVM log taraması kullanır):
//  - her swap'ın aktörü, o saatin cüzdan sayacına eklenir (Redis hash; bot/insan ayrımı
//    saat kapanışında finalizeHour tarafından yapılır),
//  - eşik üstü swap'lar WhaleTrade olarak idempotent biçimde yazılır.

import type { PrismaClient } from '@/generated/prisma/client';
import { chainFromPrisma, chainToPrisma, type ChainId } from '@/lib/chains';
import { floorToHour, HOUR_MS } from '@/lib/analytics/stats';
import { selectWhaleTrades, tallyWallets, type SwapEvent } from '@/lib/analytics/whales';
import { CACHE_KEYS, type Cache } from '../cache';

export interface IngestDeps {
  prisma: PrismaClient;
  cache: Cache;
  whaleMinUsd: number;
}

export interface WalletActivity {
  wallet: string;
  at: Date;
}

const COUNTER_TTL_SEC = 3 * 3600;
const SMART_WALLET_TTL_MS = 10 * 60_000;
let smartWalletCache: { at: number; map: Map<string, string> } | null = null;

async function loadSmartWallets(prisma: PrismaClient): Promise<Map<string, string>> {
  if (smartWalletCache && Date.now() - smartWalletCache.at < SMART_WALLET_TTL_MS) return smartWalletCache.map;
  const rows = await prisma.smartWallet.findMany({ select: { chain: true, address: true, label: true } });
  const map = new Map(rows.map((r) => [`${chainFromPrisma(r.chain)}:${r.address}`, r.label]));
  smartWalletCache = { at: Date.now(), map };
  return map;
}

export async function recordWalletActivity(cache: Cache, chain: ChainId, activity: readonly WalletActivity[]) {
  const byHour = new Map<number, WalletActivity[]>();
  for (const a of activity) {
    const hour = floorToHour(a.at).getTime();
    byHour.set(hour, [...(byHour.get(hour) ?? []), a]);
  }
  for (const [hour, items] of byHour) {
    await cache.incrementFields(CACHE_KEYS.walletCounter(chain, new Date(hour)), tallyWallets(items), COUNTER_TTL_SEC);
  }
}

export async function recordWhaleTrades(deps: IngestDeps, chain: ChainId, swaps: readonly SwapEvent[]): Promise<number> {
  const whales = selectWhaleTrades(swaps, deps.whaleMinUsd, await loadSmartWallets(deps.prisma));
  if (whales.length === 0) return 0;

  const tokens = await deps.prisma.token.findMany({
    where: { chain: chainToPrisma(chain), address: { in: [...new Set(whales.map((w) => w.tokenAddress))] } },
    select: { id: true, address: true },
  });
  const tokenIds = new Map(tokens.map((t) => [t.address, t.id]));

  const { count } = await deps.prisma.whaleTrade.createMany({
    data: whales.map((w) => ({
      id: w.id,
      chain: chainToPrisma(chain),
      tokenId: tokenIds.get(w.tokenAddress) ?? null,
      tokenAddress: w.tokenAddress,
      tokenSymbol: w.tokenSymbol,
      wallet: w.wallet,
      walletLabel: w.walletLabel,
      isSmartMoney: w.isSmartMoney,
      side: w.side,
      usdValue: w.usdValue,
      txHash: w.txHash,
      blockTime: w.blockTime,
    })),
    skipDuplicates: true,
  });
  return count;
}

/** Bir saatten eski webhook tekrarları sayaçları bozmasın diye yalnızca yakın zamanlı olaylar sayılır. */
export function recentActivity(swaps: readonly SwapEvent[], now: Date): WalletActivity[] {
  return swaps
    .filter((s) => now.getTime() - s.blockTime.getTime() < HOUR_MS)
    .map((s) => ({ wallet: s.wallet, at: s.blockTime }));
}
