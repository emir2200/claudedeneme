// İki rapor: chain sıralaması (DefiLlama) ve bir chain'in saat analizi (GeckoTerminal).
// Sonuçlar süreç içinde 30 dakika önbelleklenir; kaynak geçici olarak yanıt vermezse
// son başarılı sonuç "bayat" işaretiyle sunulur. Veri alınamazsa hata fırlatılır:
// panel asla uydurma rakam göstermez.

import { ZodError } from 'zod';
import { CHAINS, findChain } from '@/lib/chains';
import {
  PROFILE_DAYS,
  completeHourGrid,
  dayWindow,
  hourProfile,
  lastHourStatus,
  mergeHourly,
  todaySeries,
  weekMatrix,
} from '@/lib/analytics/hours';
import { buildRankings, type ChainVolumeInput } from '@/lib/analytics/rankings';
import { dayKey } from '@/lib/analytics/stats';
import type { HoursReport, RankingsReport } from '@/lib/types';
import { cached } from './cache';
import { fetchChainDexVolume } from './providers/defillama';
import { fetchHourlyVolume, fetchTopPools } from './providers/geckoterminal';
import { HttpError } from './providers/http';

const TTL_MS = 30 * 60_000;
const POOLS_PER_CHAIN = 8;
/** Profil penceresi + bugünün saatleri için yeterli saatlik mum. */
const OHLCV_LIMIT = PROFILE_DAYS * 24 + 48;

export class UnknownChainError extends Error {}

/** Kullanıcıya gösterilecek, sebebi anlatan kısa hata metni. */
export function describeError(err: unknown): string {
  if (err instanceof HttpError) {
    if (err.status === 404) return 'Kaynak bu chain’i listelemiyor';
    if (err.status === 401 || err.status === 403) {
      return `Kaynak erişimi reddetti (HTTP ${err.status}); ağ veya güvenlik duvarı bu adrese izin vermiyor olabilir`;
    }
    if (err.status === 429) return 'Kaynağın istek sınırı aşıldı; birkaç dakika sonra tekrar deneyin';
    return `Kaynak HTTP ${err.status} döndü`;
  }
  if (err instanceof ZodError) return 'Kaynaktan beklenmeyen biçimde yanıt geldi';
  if (err instanceof TypeError || (err instanceof Error && err.name === 'TimeoutError')) {
    return 'Kaynağa bağlanılamadı (internet erişimini kontrol edin)';
  }
  return err instanceof Error ? err.message : String(err);
}

export async function getRankings(now: () => Date = () => new Date()): Promise<RankingsReport> {
  const { value, stale } = await cached('rankings', TTL_MS, async () => {
    const results = await Promise.allSettled(CHAINS.map((c) => fetchChainDexVolume(c.llama)));
    const inputs: ChainVolumeInput[] = [];
    const missing: RankingsReport['missing'] = [];
    results.forEach((r, i) => {
      const chain = CHAINS[i]!;
      if (r.status === 'fulfilled' && (r.value.series.length > 0 || r.value.total24h !== null)) {
        inputs.push({ chain: chain.id, name: chain.name, series: r.value.series, fallback: r.value });
      } else {
        const reason = r.status === 'rejected' ? describeError(r.reason) : 'Kaynakta hacim verisi yok';
        missing.push({ chain: chain.id, name: chain.name, reason });
      }
    });
    if (inputs.length === 0) {
      throw new Error(`DefiLlama'dan hiçbir chain için veri alınamadı: ${missing[0]?.reason ?? 'bilinmeyen hata'}`);
    }
    const at = now();
    const { rows, asOfDay } = buildRankings(inputs, dayKey(at));
    return { generatedAt: at.toISOString(), asOfDay, rows, missing, stale: false } satisfies RankingsReport;
  });
  return { ...value, stale };
}

export async function getHours(chainId: string, now: () => Date = () => new Date()): Promise<HoursReport> {
  const chain = findChain(chainId);
  if (!chain) throw new UnknownChainError(`Bilinmeyen chain: ${chainId}`);

  const { value, stale } = await cached(`hours:${chain.id}`, TTL_MS, async () => {
    const pools = await fetchTopPools(chain.gecko, POOLS_PER_CHAIN);
    if (pools.length === 0) throw new Error('Bu chain için havuz bulunamadı');

    const results = await Promise.allSettled(pools.map((p) => fetchHourlyVolume(chain.gecko, p.address, OHLCV_LIMIT)));
    const used = pools.filter((_, i) => results[i]!.status === 'fulfilled');
    const series = results.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : []));
    if (series.length === 0) {
      const first = results.find((r): r is PromiseRejectedResult => r.status === 'rejected');
      throw new Error(`Saatlik hacim alınamadı: ${describeError(first?.reason)}`);
    }

    const at = now();
    const grid = completeHourGrid(mergeHourly(series), at);
    if (grid.length === 0) throw new Error('Son 28 günde saatlik işlem verisi yok');
    const profile = hourProfile(grid);

    return {
      chain: chain.id,
      name: chain.name,
      generatedAt: at.toISOString(),
      pools: used.map((p) => ({ name: p.name, volume24hUsd: p.volume24hUsd })),
      daysCovered: Math.floor(grid.length / 24),
      profile,
      matrix: weekMatrix(grid),
      bestWindow: dayWindow(profile, 'max'),
      quietWindow: dayWindow(profile, 'min'),
      lastHour: lastHourStatus(grid, profile),
      today: todaySeries(grid, at),
      stale: false,
    } satisfies HoursReport;
  });
  return { ...value, stale };
}
