// Hafif, bağımlılıksız zamanlayıcı.
//
// - Duvar saatine hizalı çalışır: `everyMs = 5 dk, offsetMs = 30 sn` → :00:30, :05:30, ...
// - Aynı job'un üst üste binmesini süreç içinde (`running`) ve süreçler arasında
//   (Redis `SET NX PX` kilidi) engeller; birden çok worker kopyası güvenle çalışabilir.
// - Tüm job'lar "every N minutes" türünde olduğu için cron ifadesine gerek yoktur.
//   Kuyruk/yeniden deneme/geçmiş gerekirse BullMQ'ya geçiş için bkz. docs/MIMARI.md.

import type { Cache } from './cache';
import { CACHE_KEYS } from './cache';
import { errorInfo, type Logger } from './jobs/context';

export interface JobDefinition<C> {
  name: string;
  everyMs: number;
  offsetMs?: number;
  /** Kilit süresi; job'un en uzun çalışma süresinden büyük olmalı. Varsayılan: everyMs. */
  lockTtlMs?: number;
  run: (ctx: C) => Promise<void>;
}

/** `nowMs`'ten SONRAKİ ilk hizalı çalışma anı. */
export function nextRunAt(nowMs: number, everyMs: number, offsetMs = 0): number {
  const k = Math.floor((nowMs - offsetMs) / everyMs) + 1;
  return k * everyMs + offsetMs;
}

export type RunOutcome = 'ok' | 'skipped-running' | 'skipped-locked' | 'failed';

export function createJobRunner<C>(job: JobDefinition<C>, deps: { cache: Cache; log: Logger }) {
  let running = false;
  return async function runOnce(ctx: C): Promise<RunOutcome> {
    if (running) return 'skipped-running';
    const lockKey = CACHE_KEYS.jobLock(job.name);
    const token = await deps.cache.acquireLock(lockKey, job.lockTtlMs ?? job.everyMs);
    if (!token) return 'skipped-locked';
    running = true;
    const started = Date.now();
    try {
      await job.run(ctx);
      deps.log.info(`job ${job.name} tamamlandı`, { ms: Date.now() - started });
      return 'ok';
    } catch (err) {
      deps.log.error(`job ${job.name} hata verdi`, errorInfo(err));
      return 'failed';
    } finally {
      running = false;
      await deps.cache.releaseLock(lockKey, token).catch(() => undefined);
    }
  };
}

export function startScheduler<C>(
  jobs: readonly JobDefinition<C>[],
  ctx: C,
  deps: { cache: Cache; log: Logger; runOnStart?: boolean },
): () => void {
  const timers = new Map<string, NodeJS.Timeout>();
  let stopped = false;

  for (const job of jobs) {
    const runOnce = createJobRunner(job, deps);
    const schedule = () => {
      if (stopped) return;
      const delay = nextRunAt(Date.now(), job.everyMs, job.offsetMs) - Date.now();
      timers.set(
        job.name,
        setTimeout(() => {
          void runOnce(ctx).finally(schedule);
        }, delay),
      );
    };
    if (deps.runOnStart) void runOnce(ctx).finally(schedule);
    else schedule();
  }

  return () => {
    stopped = true;
    for (const t of timers.values()) clearTimeout(t);
    timers.clear();
  };
}
