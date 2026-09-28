import { describe, expect, it } from 'vitest';
import { detectLaunchpad } from '@/lib/analytics/launchpads';
import { summarizeToken, type DexPair } from '@/server/providers/dexscreener';
import { decodeSwap, isBaseToken0 } from '@/server/providers/evmSwaps';
import { parseNewPools } from '@/server/providers/geckoterminal';
import { parseHeliusSwaps } from '@/server/providers/helius';

const pair = (over: Partial<DexPair> & { liq: number; vol: number }): DexPair => ({
  chainId: 'solana',
  dexId: 'raydium',
  pairAddress: `pair-${over.liq}`,
  baseToken: { address: 'MintPump', name: 'Meow', symbol: 'MEOW' },
  quoteToken: { address: 'So11111111111111111111111111111111111111112', symbol: 'SOL' },
  priceUsd: '0.0012',
  priceNative: '0.000008',
  txns: { h1: { buys: 10, sells: 5 }, h24: { buys: 100, sells: 80 } },
  volume: { h1: over.vol / 24, h24: over.vol },
  priceChange: { h1: 3, h24: 40 },
  liquidity: { usd: over.liq },
  marketCap: 1_200_000,
  fdv: 1_200_000,
  pairCreatedAt: 1_759_000_000_000,
  ...over,
});

describe('DEXScreener özetleme', () => {
  it('fiyatı en likit havuzdan alır, hacim ve likiditeyi toplar', () => {
    const m = summarizeToken(
      [pair({ liq: 10_000, vol: 1_000, pairAddress: 'small' }), pair({ liq: 90_000, vol: 9_000, pairAddress: 'big', dexId: 'pumpswap' })],
      'MintPump',
    )!;
    expect(m.pairAddress).toBe('big');
    expect(m.dexId).toBe('pumpswap');
    expect(m.liquidityUsd).toBe(100_000);
    expect(m.volume24hUsd).toBe(10_000);
    expect(m.buys1h + m.sells1h).toBe(30);
    expect(m.priceUsd).toBeCloseTo(0.0012);
  });

  it('token baz değilse (yalnızca quote olarak geçiyorsa) null döner', () => {
    expect(summarizeToken([pair({ liq: 1, vol: 1 })], 'BaskaMint')).toBeNull();
  });
});

describe('GeckoTerminal yeni havuzlar', () => {
  it('JSON:API yanıtını dahil edilen token kayıtlarıyla eşler', () => {
    const pools = parseNewPools(
      {
        data: [
          {
            id: 'bsc_0xpool',
            attributes: { address: '0xpool', name: 'SAFUDOG / WBNB', pool_created_at: '2026-09-28T10:00:00Z' },
            relationships: { base_token: { data: { id: 'bsc_0xabc4444' } }, dex: { data: { id: 'pancakeswap_v2' } } },
          },
          {
            id: 'bsc_0xpool2',
            attributes: { address: '0xpool2', name: 'NOINC / WBNB' },
            relationships: { base_token: { data: { id: 'bsc_0xdef' } } },
          },
        ],
        included: [{ id: 'bsc_0xabc4444', type: 'token', attributes: { address: '0xabc4444', name: 'Safu Dog', symbol: 'SAFUDOG' } }],
      },
      'bsc',
    );
    expect(pools[0]).toMatchObject({ tokenAddress: '0xabc4444', symbol: 'SAFUDOG', dexId: 'pancakeswap_v2' });
    expect(pools[0]!.poolCreatedAt?.toISOString()).toBe('2026-09-28T10:00:00.000Z');
    // included yoksa kimlikten ve havuz adından türetilir
    expect(pools[1]).toMatchObject({ tokenAddress: '0xdef', symbol: 'NOINC', poolCreatedAt: null });
  });
});

describe('launchpad sezgisi', () => {
  it('adres son eki ve DEX kimliğinden launchpad çıkarır', () => {
    expect(detectLaunchpad('solana', 'Abc123pump')).toBe('PUMP_FUN');
    expect(detectLaunchpad('solana', 'Abc123', 'pumpswap')).toBe('PUMP_FUN');
    expect(detectLaunchpad('bsc', '0xABC4444')).toBe('FOUR_MEME');
    expect(detectLaunchpad('robinhood', '0xabc4444')).toBe('OTHER');
  });
});

describe('Helius swap ayrıştırma', () => {
  const tracked = new Map([['MintA', { symbol: 'AAA', priceUsd: 0.5 }]]);
  it('imzacının net token değişiminden alım/satım ve USD değeri çıkarır', () => {
    const swaps = parseHeliusSwaps(
      [
        {
          signature: 'sig1',
          timestamp: 1_790_000_000,
          type: 'SWAP',
          feePayer: 'Trader',
          tokenTransfers: [
            { fromUserAccount: 'Pool', toUserAccount: 'Trader', mint: 'MintA', tokenAmount: 50_000 },
            { fromUserAccount: 'Trader', toUserAccount: 'Pool', mint: 'So1', tokenAmount: 100 },
          ],
        },
        {
          signature: 'sig2',
          timestamp: 1_790_000_100,
          feePayer: 'Seller',
          tokenTransfers: [{ fromUserAccount: 'Seller', toUserAccount: 'Pool', mint: 'MintA', tokenAmount: 10_000 }],
        },
        { signature: 'sig3', timestamp: 1_790_000_200, feePayer: 'X', tokenTransfers: null },
      ],
      tracked,
    );
    expect(swaps).toHaveLength(2);
    expect(swaps[0]).toMatchObject({ side: 'BUY', usdValue: 25_000, wallet: 'Trader', tokenSymbol: 'AAA' });
    expect(swaps[1]).toMatchObject({ side: 'SELL', usdValue: 5_000, wallet: 'Seller' });
    expect(swaps[0]!.blockTime.toISOString()).toBe(new Date(1_790_000_000_000).toISOString());
  });
});

describe('EVM V2 Swap çözümleme', () => {
  const quote = '0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c'; // WBNB
  const tokenLow = '0x0000000000000000000000000000000000004444';
  const tokenHigh = '0xffffffffffffffffffffffffffffffffffff4444';
  const base = { symbol: 'TKN', pairAddress: '0xpair', quoteAddress: quote, priceUsd: 0.01, priceNative: 0.00001 }; // quote = $1000

  it('token0 sırasını adresin sayısal değerine göre belirler', () => {
    expect(isBaseToken0({ tokenAddress: tokenLow, quoteAddress: quote })).toBe(true);
    expect(isBaseToken0({ tokenAddress: tokenHigh, quoteAddress: quote })).toBe(false);
  });

  it('alımı baz çıkışından tanır ve quote girişini USD’ye çevirir', () => {
    const r = decodeSwap(
      { amount0In: 0n, amount1In: 25n * 10n ** 18n, amount0Out: 5_000_000n * 10n ** 18n, amount1Out: 0n, to: '0xUSER' },
      { ...base, tokenAddress: tokenLow },
    );
    expect(r).toMatchObject({ side: 'BUY', actor: '0xuser' });
    expect(r.usdValue).toBeCloseTo(25_000, 6);
  });

  it('baz token1 olduğunda satışı quote çıkışından hesaplar', () => {
    const r = decodeSwap(
      { amount0In: 0n, amount1In: 1_000n * 10n ** 18n, amount0Out: 2n * 10n ** 18n, amount1Out: 0n, to: '0xrouter' },
      { ...base, tokenAddress: tokenHigh },
    );
    expect(r.side).toBe('SELL');
    expect(r.usdValue).toBeCloseTo(2_000, 6);
  });
});
