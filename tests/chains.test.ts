import { describe, expect, it } from 'vitest';
import { tokenLinks } from '@/lib/chains';

describe('tokenLinks', () => {
  it('Solana ve BNB Chain için blok gezgini ve DEXScreener bağlantısı üretir', () => {
    expect(tokenLinks('solana', 'MintAbcpump')).toEqual([
      { label: 'Solscan', href: 'https://solscan.io/token/MintAbcpump' },
      { label: 'DEXScreener', href: 'https://dexscreener.com/solana/MintAbcpump' },
    ]);
    expect(tokenLinks('bsc', '0xabc4444').map((l) => l.href)).toEqual([
      'https://bscscan.com/token/0xabc4444',
      'https://dexscreener.com/bsc/0xabc4444',
    ]);
  });

  it('doğrulanmamış Robinhood Chain kimlikleri için tahmini bağlantı üretmez', () => {
    expect(tokenLinks('robinhood', '0xabc')).toEqual([]);
  });
});
