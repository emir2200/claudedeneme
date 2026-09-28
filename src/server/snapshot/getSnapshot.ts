// /api/dashboard ve sayfa sunucu render'ının kullandığı tek giriş noktası.
//
// demo : simülatör → buildSnapshot (süreç içinde 30 sn önbellek)
// live : Redis'teki hazır snapshot (worker 30 sn'de bir yazar). Önbellek boşsa tek bir
//        istek kilidi alıp PostgreSQL'den üretir; diğer eşzamanlı istekler kısa süre bekleyip
//        önbelleği okur (cache stampede koruması).

import { buildSnapshot } from '@/lib/analytics/snapshot';
import type { DashboardSnapshot } from '@/lib/types';
import { CACHE_KEYS, getCache } from '../cache';
import { getConfig } from '../config';
import { getPrisma } from '../db';
import { sleep } from '../providers/http';
import { simulateRawData } from '../simulation';
import { loadRawFromDb } from './loadFromDb';

export const SNAPSHOT_TTL_SEC = 120;
const DEMO_TTL_MS = 30_000;

let demoMemo: { at: number; snapshot: DashboardSnapshot } | null = null;

export function snapshotOptions() {
  const config = getConfig();
  return { milestoneUsd: config.MILESTONE_USD, whaleMinUsd: config.WHALE_MIN_USD };
}

export async function buildLiveSnapshot(now: Date = new Date()): Promise<DashboardSnapshot> {
  return buildSnapshot(await loadRawFromDb(getPrisma(), now), snapshotOptions());
}

export async function getDashboardSnapshot(): Promise<DashboardSnapshot> {
  const config = getConfig();

  if (config.DATA_MODE === 'demo') {
    if (!demoMemo || Date.now() - demoMemo.at > DEMO_TTL_MS) {
      demoMemo = { at: Date.now(), snapshot: buildSnapshot(simulateRawData(new Date()), snapshotOptions()) };
    }
    return demoMemo.snapshot;
  }

  const cache = getCache();
  const cached = await cache.get(CACHE_KEYS.snapshot);
  if (cached) return JSON.parse(cached) as DashboardSnapshot;

  const token = await cache.acquireLock(CACHE_KEYS.snapshotLock, 15_000);
  if (token) {
    try {
      const snapshot = await buildLiveSnapshot();
      await cache.set(CACHE_KEYS.snapshot, JSON.stringify(snapshot), SNAPSHOT_TTL_SEC);
      return snapshot;
    } finally {
      await cache.releaseLock(CACHE_KEYS.snapshotLock, token);
    }
  }

  for (let i = 0; i < 20; i++) {
    await sleep(250);
    const value = await cache.get(CACHE_KEYS.snapshot);
    if (value) return JSON.parse(value) as DashboardSnapshot;
  }
  return buildLiveSnapshot();
}
