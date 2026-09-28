import { describe, expect, it } from 'vitest';
import { scoreHype, type HypeCandidate } from '@/lib/analytics/hype';

const now = new Date('2026-09-28T12:00:00Z');
const cand = (symbol: string, over: Partial<HypeCandidate> = {}): HypeCandidate => ({
  chain: 'solana',
  address: symbol.toLowerCase(),
  symbol,
  name: symbol,
  narratives: [],
  launchpad: 'PUMP_FUN',
  priceUsd: 0.001,
  priceChange24hPct: 10,
  marketCapUsd: 1_000_000,
  liquidityUsd: 100_000,
  volume24hUsd: 500_000,
  mentions24h: 100,
  mentionsPrev24h: 100,
  engagements24h: 2_000,
  sentiment: 0.6,
  mentionSeries: new Array(24).fill(4),
  poolCreatedAt: new Date(now.getTime() - 48 * 3_600_000),
  ...over,
});

describe('scoreHype', () => {
  it('eşiği geçmeyen token’ları eler', () => {
    const scored = scoreHype([cand('LOWLIQ', { liquidityUsd: 5_000 }), cand('LOWCAP', { marketCapUsd: 50_000 }), cand('OK')], now);
    expect(scored.map((s) => s.symbol)).toEqual(['OK']);
  });

  it('sosyal ivmesi ve etkileşimi en yüksek token birinci olur', () => {
    const scored = scoreHype(
      [
        cand('FLAT'),
        cand('HOT', { engagements24h: 50_000, mentions24h: 900, mentionsPrev24h: 100, priceChange24hPct: 120 }),
        cand('MID', { engagements24h: 8_000, mentions24h: 200 }),
      ],
      now,
    );
    expect(scored[0]!.symbol).toBe('HOT');
    expect(scored[0]!.hypeScore).toBeGreaterThan(scored[1]!.hypeScore);
    expect(scored[0]!.mentionVelocity).toBeCloseTo(901 / 101);
  });

  it('wash-trade devrini sınırlar ve risk bayrakları koyar', () => {
    const [w] = scoreHype([cand('WASH', { volume24hUsd: 20_000_000, liquidityUsd: 30_000, poolCreatedAt: new Date(now.getTime() - 3_600_000) })], now);
    expect(w!.volMcapRatio).toBe(20);
    expect(w!.riskFlags).toEqual(expect.arrayContaining(['asiri-devir', 'ince-likidite', 'yeni-token']));
  });
});
