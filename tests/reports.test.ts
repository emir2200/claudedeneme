// Raporların uçtan uca testi: dış API'ler fetch stub'ıyla taklit edilir.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { clearCache } from '@/server/cache';
import { getHours, getRankings } from '@/server/reports';

const now = () => new Date('2026-09-28T12:30:00Z');
const DAY = 86_400;
const lastDay = Date.parse('2026-09-27T00:00:00Z') / 1000;

/** chain → günlük hacim */
const dailyVolume: Record<string, number> = { solana: 3e9, bsc: 2e9, ethereum: 1.5e9 };

function respond(url: URL): Response {
  const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200 });
  if (url.hostname === 'api.llama.fi') {
    const chain = url.pathname.split('/').pop()!;
    const v = dailyVolume[chain];
    if (v === undefined) return new Response('{}', { status: 404 });
    return json({
      total24h: v,
      total7d: v * 7,
      total30d: v * 30,
      totalDataChart: Array.from({ length: 60 }, (_, i) => [lastDay - (59 - i) * DAY, v]),
    });
  }
  if (url.hostname === 'api.geckoterminal.com') {
    if (url.pathname.endsWith('/pools')) {
      return json({ data: [{ attributes: { address: 'p1', name: 'MEOW / SOL', volume_usd: { h24: '5000000' } } }] });
    }
    // Saatlik OHLCV: 15:00–17:59 UTC yoğun.
    const end = Date.parse('2026-09-28T12:00:00Z') / 1000;
    const list = Array.from({ length: 30 * 24 }, (_, i) => {
      const ts = end - i * 3600;
      const h = new Date(ts * 1000).getUTCHours();
      return [ts, 1, 1, 1, 1, h >= 15 && h < 18 ? 900 : 100];
    });
    return json({ data: { attributes: { ohlcv_list: list } } });
  }
  return new Response('yok', { status: 404 });
}

beforeEach(() => {
  clearCache();
  vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request) => respond(new URL(String(input instanceof Request ? input.url : input)))));
});
afterEach(() => vi.unstubAllGlobals());

describe('getRankings', () => {
  it('gerçek kaynaktan gelen verilerle sıralar; listelenmeyen chain’leri sebebiyle bildirir', async () => {
    const r = await getRankings(now);
    expect(r.rows.map((x) => x.chain)).toEqual(['solana', 'bsc', 'ethereum']);
    expect(r.rows[0]!.stats.week.volumeUsd).toBe(3e9 * 7);
    expect(r.asOfDay).toBe('2026-09-27');
    expect(r.missing.find((m) => m.chain === 'robinhood')?.reason).toBe('Kaynak bu chain’i listelemiyor');
    expect(r.stale).toBe(false);
  });

  it('hiç veri gelmezse uydurmak yerine hata verir', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{}', { status: 404 })));
    await expect(getRankings(now)).rejects.toThrow(/hiçbir chain için veri alınamadı/);
  });

  it('kaynak düşerse son başarılı sonucu bayat olarak sunar', async () => {
    await getRankings(now);
    vi.useFakeTimers({ now: Date.now() + 31 * 60_000, toFake: ['Date'] });
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('fetch failed'); }));
    try {
      const r = await getRankings(now);
      expect(r.stale).toBe(true);
      expect(r.rows).toHaveLength(3);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('getHours', () => {
  it('en aktif saatleri havuzların saatlik hacminden çıkarır', async () => {
    const h = await getHours('solana', now);
    expect(h.bestWindow).toMatchObject({ startHour: 15, length: 3 });
    expect(h.pools).toEqual([{ name: 'MEOW / SOL', volume24hUsd: 5e6 }]);
    expect(h.daysCovered).toBe(28);
    expect(h.lastHour?.hourStart).toBe('2026-09-28T11:00:00.000Z');
  });

  it('bilinmeyen chain için açık hata verir', async () => {
    await expect(getHours('yok-boyle-chain', now)).rejects.toThrow(/Bilinmeyen chain/);
  });
});
