// EVM zincirleri (BSC, Robinhood Chain) için Uniswap-V2 tipi `Swap` loglarını tarar.
// PancakeSwap V2 (Four.meme mezunlarının gittiği havuzlar) aynı olay imzasını kullanır.
//
// USD değeri quote tarafından hesaplanır: quote token'ın USD fiyatı = baz fiyatUSD /
// baz fiyatNative (DEXScreener). BSC'de yaygın quote'lar (WBNB, USDT, USDC) 18 ondalıklıdır.
// Cüzdan: `to` (alıcı) adresi aktörün vekilidir; router üzerinden geçen satışlarda bu
// router olabilir, bu yüzden yalnızca balina boyutundaki swap'lar için gerçek imzacı
// (tx.from) ayrıca sorgulanır.

import { createPublicClient, http, parseAbiItem, type Address, type Hex } from 'viem';
import type { ChainId } from '@/lib/chains';
import type { SwapEvent } from '@/lib/analytics/whales';

export const SWAP_EVENT = parseAbiItem(
  'event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to)',
);

export interface TrackedPair {
  pairAddress: string;
  tokenAddress: string;
  quoteAddress: string;
  symbol: string;
  priceUsd: number;
  priceNative: number;
}

export interface SwapArgs {
  amount0In: bigint;
  amount1In: bigint;
  amount0Out: bigint;
  amount1Out: bigint;
  to: string;
}

/** V2 havuzunda token0, adresi sayısal olarak küçük olan token'dır. */
export function isBaseToken0(pair: Pick<TrackedPair, 'tokenAddress' | 'quoteAddress'>): boolean {
  return BigInt(pair.tokenAddress) < BigInt(pair.quoteAddress);
}

export function decodeSwap(args: SwapArgs, pair: TrackedPair, quoteDecimals = 18) {
  const base0 = isBaseToken0(pair);
  const baseOut = base0 ? args.amount0Out : args.amount1Out;
  const quoteIn = base0 ? args.amount1In : args.amount0In;
  const quoteOut = base0 ? args.amount1Out : args.amount0Out;
  const side = baseOut > 0n ? ('BUY' as const) : ('SELL' as const);
  const quoteAmount = Number(side === 'BUY' ? quoteIn : quoteOut) / 10 ** quoteDecimals;
  const quoteUsd = pair.priceNative > 0 ? pair.priceUsd / pair.priceNative : 0;
  return { side, usdValue: quoteAmount * quoteUsd, actor: args.to.toLowerCase() };
}

export interface ScanResult {
  swaps: SwapEvent[];
  /** Tüm swap'ların aktörleri (bot/insan sayacı için). */
  actors: string[];
  toBlock: bigint;
}

export async function scanSwaps(options: {
  chain: ChainId;
  rpcUrl: string;
  pairs: readonly TrackedPair[];
  fromBlock: bigint | null;
  maxRange: bigint;
  whaleMinUsd: number;
}): Promise<ScanResult> {
  const client = createPublicClient({ transport: http(options.rpcUrl) });
  const latest = await client.getBlockNumber();
  const fromBlock = options.fromBlock ?? latest - 100n;
  const toBlock = fromBlock + options.maxRange < latest ? fromBlock + options.maxRange : latest;
  if (fromBlock > toBlock || options.pairs.length === 0) return { swaps: [], actors: [], toBlock: latest };

  const byPair = new Map(options.pairs.map((p) => [p.pairAddress.toLowerCase(), p]));
  const logs = await client.getLogs({
    address: options.pairs.map((p) => p.pairAddress as Address),
    event: SWAP_EVENT,
    fromBlock,
    toBlock,
  });

  const actors: string[] = [];
  const swaps: SwapEvent[] = [];
  const blockTimes = new Map<bigint, Date>();
  for (const log of logs) {
    const pair = byPair.get(log.address.toLowerCase());
    if (!pair || !log.args.to || log.args.amount0In === undefined) continue;
    const decoded = decodeSwap(log.args as SwapArgs, pair);
    actors.push(decoded.actor);
    if (decoded.usdValue < options.whaleMinUsd || !log.transactionHash || log.blockNumber === null) continue;

    const [tx, blockTime] = await Promise.all([
      client.getTransaction({ hash: log.transactionHash as Hex }),
      blockTimes.get(log.blockNumber) ??
        client.getBlock({ blockNumber: log.blockNumber }).then((b) => new Date(Number(b.timestamp) * 1000)),
    ]);
    blockTimes.set(log.blockNumber, blockTime);
    swaps.push({
      chain: options.chain,
      txHash: log.transactionHash,
      index: log.logIndex ?? 0,
      wallet: tx.from.toLowerCase(),
      tokenAddress: pair.tokenAddress,
      tokenSymbol: pair.symbol,
      side: decoded.side,
      usdValue: decoded.usdValue,
      blockTime,
    });
  }
  return { swaps, actors, toBlock };
}
