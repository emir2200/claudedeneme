// Job: EVM balina taraması (her dakika). BSC ve Robinhood Chain için RPC tanımlıysa,
// hacme göre ilk 100 token'ın ana havuzunda son bloktan bu yana oluşan Swap loglarını
// okur. Kaldığı blok SyncCursor tablosunda tutulur (yeniden başlatmada kayıp olmaz).

import { chainToPrisma, type ChainId } from '@/lib/chains';
import { providerIds } from '../config';
import { recordWalletActivity, recordWhaleTrades } from '../ingest/swaps';
import { scanSwaps } from '../providers/evmSwaps';
import { errorInfo, type JobContext } from './context';

const EVM_CHAINS: ChainId[] = ['bsc', 'robinhood'];
const PAIRS_PER_CHAIN = 100;
const MAX_BLOCK_RANGE = 2_000n;

export async function evmWhales(ctx: JobContext): Promise<void> {
  const ids = providerIds(ctx.config);
  for (const chain of EVM_CHAINS) {
    const rpcUrl = ids[chain].rpcUrl;
    if (!rpcUrl) continue;
    try {
      const tokens = await ctx.prisma.token.findMany({
        where: {
          chain: chainToPrisma(chain),
          isActive: true,
          pairAddress: { not: null },
          quoteAddress: { not: null },
          priceUsd: { gt: 0 },
          priceNative: { gt: 0 },
        },
        orderBy: { volume24hUsd: { sort: 'desc', nulls: 'last' } },
        take: PAIRS_PER_CHAIN,
        select: { address: true, symbol: true, pairAddress: true, quoteAddress: true, priceUsd: true, priceNative: true },
      });

      const cursorKey = `evm:${chain}:lastBlock`;
      const cursor = await ctx.prisma.syncCursor.findUnique({ where: { key: cursorKey } });
      const now = ctx.now();
      const result = await scanSwaps({
        chain,
        rpcUrl,
        pairs: tokens.map((t) => ({
          pairAddress: t.pairAddress!,
          tokenAddress: t.address,
          quoteAddress: t.quoteAddress!,
          symbol: t.symbol,
          priceUsd: t.priceUsd!,
          priceNative: t.priceNative!,
        })),
        fromBlock: cursor ? BigInt(cursor.value) + 1n : null,
        maxRange: MAX_BLOCK_RANGE,
        whaleMinUsd: ctx.config.WHALE_MIN_USD,
      });

      await recordWalletActivity(ctx.cache, chain, result.actors.map((wallet) => ({ wallet, at: now })));
      const inserted = await recordWhaleTrades(
        { prisma: ctx.prisma, cache: ctx.cache, whaleMinUsd: ctx.config.WHALE_MIN_USD },
        chain,
        result.swaps,
      );
      await ctx.prisma.syncCursor.upsert({
        where: { key: cursorKey },
        create: { key: cursorKey, value: result.toBlock.toString() },
        update: { value: result.toBlock.toString() },
      });
      ctx.log.info(`evmWhales: ${chain}`, { swaps: result.actors.length, whales: inserted, toBlock: result.toBlock.toString() });
    } catch (err) {
      ctx.log.warn(`evmWhales: ${chain} başarısız`, errorInfo(err));
    }
  }
}
