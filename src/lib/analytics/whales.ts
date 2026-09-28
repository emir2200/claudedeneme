// Balina / smart money swapları ve bot–insan ayrımı
//
// Swap olayları zincirden bağımsız tek bir biçime (SwapEvent) normalize edilir:
// Solana için Helius webhook'u, EVM (BSC / Robinhood Chain) için Uniswap-V2 tipi
// `Swap` logları. Bu modül yalnızca saf hesaplamaları içerir.
//
// Bot sezgisi (saatlik): bir cüzdan aynı saat içinde ≥ `botTxPerHour` swap yaptıysa
// o cüzdanın tüm işlemleri bot sayılır. Sniper/MEV/volume-bot'lar bu eşiği kolayca aşar;
// insan trader'lar nadiren aşar. Bilinen bot listeleriyle zenginleştirilebilir.

import type { ChainId } from '../chains';
import type { TradeSide } from '../types';

export interface SwapEvent {
  chain: ChainId;
  txHash: string;
  /** Aynı işlemdeki birden çok swap'ı ayırt eder (EVM log index / Solana talimat sırası). */
  index: number;
  wallet: string;
  tokenAddress: string;
  tokenSymbol: string | null;
  side: TradeSide;
  usdValue: number;
  blockTime: Date;
}

export function swapId(e: Pick<SwapEvent, 'chain' | 'txHash' | 'index'>): string {
  return `${e.chain}:${e.txHash}:${e.index}`;
}

export function selectWhaleTrades(
  swaps: readonly SwapEvent[],
  minUsd: number,
  smartWallets: ReadonlyMap<string, string> = new Map(),
) {
  return swaps
    .filter((s) => s.usdValue >= minUsd)
    .map((s) => {
      const label = smartWallets.get(`${s.chain}:${s.wallet}`) ?? null;
      return { ...s, id: swapId(s), walletLabel: label, isSmartMoney: label !== null };
    });
}

/** Cüzdan başına swap sayısı. */
export function tallyWallets(swaps: readonly Pick<SwapEvent, 'wallet'>[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const s of swaps) counts.set(s.wallet, (counts.get(s.wallet) ?? 0) + 1);
  return counts;
}

export function splitBotHuman(
  walletCounts: ReadonlyMap<string, number> | Record<string, number>,
  botTxPerHour: number,
): { botTxCount: number; humanTxCount: number; botWallets: number; humanWallets: number } {
  const entries = walletCounts instanceof Map ? [...walletCounts.values()] : Object.values(walletCounts);
  let botTxCount = 0;
  let humanTxCount = 0;
  let botWallets = 0;
  let humanWallets = 0;
  for (const n of entries) {
    if (n >= botTxPerHour) {
      botTxCount += n;
      botWallets++;
    } else {
      humanTxCount += n;
      humanWallets++;
    }
  }
  return { botTxCount, humanTxCount, botWallets, humanWallets };
}

export function netFlow(
  trades: ReadonlyArray<{ chain: ChainId; side: TradeSide; usdValue: number; blockTime: Date }>,
  since: Date,
): Record<ChainId, { buyUsd: number; sellUsd: number; count: number }> {
  const out: Record<ChainId, { buyUsd: number; sellUsd: number; count: number }> = {
    solana: { buyUsd: 0, sellUsd: 0, count: 0 },
    bsc: { buyUsd: 0, sellUsd: 0, count: 0 },
    robinhood: { buyUsd: 0, sellUsd: 0, count: 0 },
  };
  for (const t of trades) {
    if (t.blockTime < since) continue;
    const bucket = out[t.chain];
    if (t.side === 'BUY') bucket.buyUsd += t.usdValue;
    else bucket.sellUsd += t.usdValue;
    bucket.count++;
  }
  return out;
}
