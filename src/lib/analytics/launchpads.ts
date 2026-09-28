// Launchpad ataması (sezgisel).
// - Pump.fun mint adresleri "pump" son ekiyle üretilir; DEXScreener'da bonding curve
//   havuzları "pumpfun", mezun olanlar "pumpswap" DEX kimliğiyle görünür.
// - Four.meme (BNB Chain) kontrat adresleri "4444" son ekiyle üretilir.
// Kimlikler sağlayıcılar tarafından değiştirilebilir; yeni launchpad eklemek için
// yalnızca bu tabloyu güncellemek yeterlidir.

import type { ChainId } from '../chains';
import type { Launchpad } from '../types';

const DEX_ID_TO_LAUNCHPAD: Record<string, Launchpad> = {
  pumpfun: 'PUMP_FUN',
  pumpswap: 'PUMP_FUN',
  fourmeme: 'FOUR_MEME',
};

export function detectLaunchpad(chain: ChainId, address: string, dexId?: string | null): Launchpad {
  const fromDex = dexId ? DEX_ID_TO_LAUNCHPAD[dexId.toLowerCase()] : undefined;
  if (fromDex) return fromDex;
  if (chain === 'solana' && address.endsWith('pump')) return 'PUMP_FUN';
  if (chain === 'bsc' && address.toLowerCase().endsWith('4444')) return 'FOUR_MEME';
  return 'OTHER';
}

export const LAUNCHPAD_NAMES: Record<Launchpad, string> = {
  PUMP_FUN: 'Pump.fun',
  FOUR_MEME: 'Four.meme',
  OTHER: 'Diğer',
};
