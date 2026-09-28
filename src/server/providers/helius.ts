// Helius "enhanced transaction" webhook yükünden Solana swap'larını çıkarır.
//
// Swap'ı `events.swap` alanından değil, token transferlerinden türetiriz: pump.fun /
// PumpSwap gibi programlarda `events.swap` çoğu zaman boştur, `tokenTransfers` ise her
// zaman doludur. İşlemi imzalayan (feePayer) cüzdanın takip edilen mint'teki NET
// değişimi: pozitifse ALIM, negatifse SATIM; USD değeri = |miktar| × token fiyatı.

import { z } from 'zod';
import type { SwapEvent } from '@/lib/analytics/whales';

const transferSchema = z.object({
  fromUserAccount: z.string().nullish(),
  toUserAccount: z.string().nullish(),
  mint: z.string(),
  tokenAmount: z.number(),
});

const txSchema = z.object({
  signature: z.string(),
  timestamp: z.number(),
  type: z.string().nullish(),
  feePayer: z.string(),
  tokenTransfers: z.array(transferSchema).nullish(),
});

export const heliusPayloadSchema = z.array(txSchema);
export type HeliusPayload = z.infer<typeof heliusPayloadSchema>;

export interface TrackedMint {
  symbol: string;
  priceUsd: number;
}

export function parseHeliusSwaps(payload: HeliusPayload, tracked: ReadonlyMap<string, TrackedMint>): SwapEvent[] {
  const out: SwapEvent[] = [];
  for (const tx of payload) {
    const net = new Map<string, number>();
    for (const t of tx.tokenTransfers ?? []) {
      if (!tracked.has(t.mint)) continue;
      let delta = 0;
      if (t.toUserAccount === tx.feePayer) delta += t.tokenAmount;
      if (t.fromUserAccount === tx.feePayer) delta -= t.tokenAmount;
      if (delta !== 0) net.set(t.mint, (net.get(t.mint) ?? 0) + delta);
    }
    let index = 0;
    for (const [mint, amount] of net) {
      const token = tracked.get(mint)!;
      if (amount === 0) continue;
      out.push({
        chain: 'solana',
        txHash: tx.signature,
        index: index++,
        wallet: tx.feePayer,
        tokenAddress: mint,
        tokenSymbol: token.symbol,
        side: amount > 0 ? 'BUY' : 'SELL',
        usdValue: Math.abs(amount) * token.priceUsd,
        blockTime: new Date(tx.timestamp * 1000),
      });
    }
  }
  return out;
}
