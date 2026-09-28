import { describe, expect, it } from 'vitest';
import { netFlow, selectWhaleTrades, splitBotHuman, tallyWallets, type SwapEvent } from '@/lib/analytics/whales';

const t0 = new Date('2026-09-28T12:00:00Z');
const swap = (wallet: string, usdValue: number, side: SwapEvent['side'] = 'BUY', min = 0): SwapEvent => ({
  chain: 'bsc',
  txHash: `0x${wallet}${usdValue}`,
  index: 0,
  wallet,
  tokenAddress: '0xtoken',
  tokenSymbol: 'TKN',
  side,
  usdValue,
  blockTime: new Date(t0.getTime() + min * 60_000),
});

describe('balina ve bot analizi', () => {
  it('eşik üstü swapları seçer ve smart money etiketler', () => {
    const whales = selectWhaleTrades([swap('a', 5_000), swap('b', 25_000)], 10_000, new Map([['bsc:b', 'Fon']]));
    expect(whales).toHaveLength(1);
    expect(whales[0]).toMatchObject({ wallet: 'b', isSmartMoney: true, walletLabel: 'Fon', id: 'bsc:0xb25000:0' });
  });

  it('saatlik eşiği aşan cüzdanları bot sayar', () => {
    const swaps = [...Array.from({ length: 40 }, () => swap('bot', 100)), swap('human1', 100), swap('human2', 100)];
    expect(splitBotHuman(tallyWallets(swaps), 30)).toEqual({ botTxCount: 40, humanTxCount: 2, botWallets: 1, humanWallets: 2 });
  });

  it('net akışı zaman penceresine göre toplar', () => {
    const flow = netFlow([swap('a', 100, 'BUY', 10), swap('b', 40, 'SELL', 20), swap('c', 999, 'BUY', -120)], new Date(t0.getTime() - 3_600_000));
    expect(flow.bsc).toEqual({ buyUsd: 100, sellUsd: 40, count: 2 });
    expect(flow.solana.count).toBe(0);
  });
});
