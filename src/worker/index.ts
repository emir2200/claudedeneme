// Veri toplama worker'ı: `npm run worker`
// Web uygulamasından ayrı bir süreçtir; PostgreSQL'i doldurur ve Redis'e hazır
// snapshot yazar. Birden çok kopya çalıştırılabilir (job kilitleri Redis'tedir).

import 'dotenv/config';
import { getCache } from '@/server/cache';
import { getConfig } from '@/server/config';
import { getPrisma } from '@/server/db';
import { consoleLogger, type JobContext } from '@/server/jobs/context';
import { discoverTokens } from '@/server/jobs/discoverTokens';
import { evmWhales } from '@/server/jobs/evmWhales';
import { finalizeHour } from '@/server/jobs/finalizeHour';
import { prune } from '@/server/jobs/prune';
import { publishSnapshot } from '@/server/jobs/publishSnapshot';
import { refreshMarkets } from '@/server/jobs/refreshMarkets';
import { socialPulse } from '@/server/jobs/socialPulse';
import { startScheduler, type JobDefinition } from '@/server/scheduler';

const SEC = 1_000;
const MIN = 60 * SEC;

export const JOBS: JobDefinition<JobContext>[] = [
  { name: 'discoverTokens', everyMs: 2 * MIN, offsetMs: 10 * SEC, run: discoverTokens },
  { name: 'refreshMarkets', everyMs: 5 * MIN, offsetMs: 30 * SEC, lockTtlMs: 10 * MIN, run: refreshMarkets },
  { name: 'evmWhales', everyMs: MIN, offsetMs: 5 * SEC, lockTtlMs: 3 * MIN, run: evmWhales },
  { name: 'finalizeHour', everyMs: 60 * MIN, offsetMs: 90 * SEC, run: finalizeHour },
  { name: 'socialPulse', everyMs: 15 * MIN, offsetMs: 3 * MIN, run: socialPulse },
  { name: 'publishSnapshot', everyMs: 30 * SEC, offsetMs: 15 * SEC, lockTtlMs: MIN, run: publishSnapshot },
  { name: 'prune', everyMs: 24 * 60 * MIN, offsetMs: 3 * 60 * MIN, lockTtlMs: 30 * MIN, run: prune },
];

async function main() {
  const config = getConfig();
  const ctx: JobContext = {
    prisma: getPrisma(),
    cache: getCache(),
    config,
    now: () => new Date(),
    log: consoleLogger,
  };
  if (!config.REDIS_URL) consoleLogger.warn('REDIS_URL yok: bellek önbelleği kullanılıyor, web süreci snapshot’ı göremez.');

  consoleLogger.info('worker başladı', { jobs: JOBS.map((j) => j.name) });
  const stop = startScheduler(JOBS, ctx, { cache: ctx.cache, log: ctx.log, runOnStart: true });

  const shutdown = async (signal: string) => {
    consoleLogger.info(`${signal} alındı, kapanıyor`);
    stop();
    await Promise.allSettled([ctx.prisma.$disconnect(), ctx.cache.close()]);
    process.exit(0);
  };
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

main().catch((err) => {
  consoleLogger.error('worker başlatılamadı', { error: err instanceof Error ? err.message : String(err) });
  process.exit(1);
});
