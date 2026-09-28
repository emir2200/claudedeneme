// Job: snapshot yayını (her 30 saniyede bir). Dashboard'un okuduğu hazır JSON'u
// PostgreSQL'den üretip Redis'e yazar; web katmanı istek başına sorgu çalıştırmaz.

import { buildSnapshot } from '@/lib/analytics/snapshot';
import { CACHE_KEYS } from '../cache';
import { loadRawFromDb } from '../snapshot/loadFromDb';
import { SNAPSHOT_TTL_SEC } from '../snapshot/getSnapshot';
import type { JobContext } from './context';

export async function publishSnapshot(ctx: JobContext): Promise<void> {
  const raw = await loadRawFromDb(ctx.prisma, ctx.now());
  const snapshot = buildSnapshot(raw, {
    milestoneUsd: ctx.config.MILESTONE_USD,
    whaleMinUsd: ctx.config.WHALE_MIN_USD,
  });
  await ctx.cache.set(CACHE_KEYS.snapshot, JSON.stringify(snapshot), SNAPSHOT_TTL_SEC);
}
