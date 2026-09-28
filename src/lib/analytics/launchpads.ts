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

/**
 * Memecoin olmayan, havuzlarda baz token olarak da görünebilen yaygın token'lar
 * (sarılı native coin'ler ve stablecoin'ler). Keşif sırasında evrene alınmaz.
 */
const NON_MEME_TOKENS: Record<ChainId, ReadonlySet<string>> = {
  solana: new Set([
    'So11111111111111111111111111111111111111112', // WSOL
    'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', // USDC
    'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB', // USDT
  ]),
  bsc: new Set([
    '0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c', // WBNB
    '0x55d398326f99059ff775485246999027b3197955', // USDT
    '0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d', // USDC
    '0xe9e7cea3dedca5984780bafc599bd69add087d56', // BUSD
  ]),
  robinhood: new Set(),
};

const STABLE_SYMBOLS = new Set(['USDC', 'USDT', 'USD1', 'FDUSD', 'BUSD', 'DAI', 'WETH', 'WBNB', 'WSOL', 'SOL', 'ETH', 'BNB']);

/** Adres (kanonik biçimde) veya sembol bilinen bir memecoin olmayan token'a mı ait? */
export function isNonMemeToken(chain: ChainId, address: string, symbol: string): boolean {
  return NON_MEME_TOKENS[chain].has(address) || STABLE_SYMBOLS.has(symbol.toUpperCase());
}

export const LAUNCHPAD_NAMES: Record<Launchpad, string> = {
  PUMP_FUN: 'Pump.fun',
  FOUR_MEME: 'Four.meme',
  OTHER: 'Diğer',
};
