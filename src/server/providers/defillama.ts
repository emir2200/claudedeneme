// DefiLlama — chain başına günlük DEX hacmi.
// Uç nokta: GET /overview/dexs/{chain}?excludeTotalDataChartBreakdown=true&dataType=dailyVolume
// Yanıt: total24h / total7d / total30d ve totalDataChart = [[unixSaniye, hacimUsd], …].
// Anahtar gerekmez.

import { z } from 'zod';
import { dayKey } from '@/lib/analytics/stats';
import type { DailyPoint } from '@/lib/analytics/rankings';
import { baseUrls } from '../config';
import { fetchJson, RateLimiter } from './http';

const num = z.number().nullish();

export const dexOverviewSchema = z.object({
  total24h: num,
  total7d: num,
  total30d: num,
  totalDataChart: z.array(z.array(z.union([z.number(), z.string()]))).nullish(),
});

export interface ChainDexVolume {
  series: DailyPoint[];
  total24h: number | null;
  total7d: number | null;
  total30d: number | null;
}

const limiter = new RateLimiter(120);

export function parseDexOverview(res: z.infer<typeof dexOverviewSchema>): ChainDexVolume {
  const series: DailyPoint[] = [];
  for (const row of res.totalDataChart ?? []) {
    const ts = Number(row[0]);
    const volume = Number(row[1]);
    if (!Number.isFinite(ts) || !Number.isFinite(volume)) continue;
    series.push({ day: dayKey(new Date(ts * 1000)), volumeUsd: volume });
  }
  return { series, total24h: res.total24h ?? null, total7d: res.total7d ?? null, total30d: res.total30d ?? null };
}

export async function fetchChainDexVolume(llamaId: string): Promise<ChainDexVolume> {
  const url = `${baseUrls().defillama}/overview/dexs/${encodeURIComponent(llamaId)}?excludeTotalDataChartBreakdown=true&dataType=dailyVolume`;
  return parseDexOverview(await fetchJson(url, { schema: dexOverviewSchema, limiter, retries: 2 }));
}
