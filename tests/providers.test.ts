import { describe, expect, it } from 'vitest';
import { parseDexOverview } from '@/server/providers/defillama';
import { parseOhlcv, parsePools } from '@/server/providers/geckoterminal';

describe('DefiLlama', () => {
  it('günlük seriyi UTC günlerine çevirir, bozuk satırları atlar', () => {
    const r = parseDexOverview({
      total24h: 3,
      total7d: 10,
      total30d: null,
      totalDataChart: [
        [1790467200, 1.5], // 2026-09-27
        [1790553600, '2'], // 2026-09-28
        ['x', 5],
      ],
    });
    expect(r.series).toEqual([
      { day: '2026-09-27', volumeUsd: 1.5 },
      { day: '2026-09-28', volumeUsd: 2 },
    ]);
    expect(r).toMatchObject({ total24h: 3, total7d: 10, total30d: null });
  });
});

describe('GeckoTerminal', () => {
  it('havuzları 24s hacme göre sıralar', () => {
    const pools = parsePools({
      data: [
        { attributes: { address: 'a', name: 'A / SOL', volume_usd: { h24: '100.5' } } },
        { attributes: { address: 'b', name: 'B / SOL', volume_usd: { h24: '900' } } },
        { attributes: { address: 'c', name: 'C / SOL', volume_usd: null } },
      ],
    });
    expect(pools.map((p) => p.address)).toEqual(['b', 'a', 'c']);
    expect(pools[1]!.volume24hUsd).toBe(100.5);
  });

  it('OHLCV satırlarından saatlik hacim çıkarır', () => {
    expect(
      parseOhlcv({ data: { attributes: { ohlcv_list: [[1790596800, 1, 2, 0.5, 1.5, 12345], [1790593200, 1, 1, 1, 1]] } } }),
    ).toEqual([{ hourStart: 1790596800000, volumeUsd: 12345 }]);
  });
});
