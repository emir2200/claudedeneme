import { describe, expect, it } from 'vitest';
import { MemoryCache } from '@/server/cache';
import type { Logger } from '@/server/jobs/context';
import { createJobRunner, nextRunAt } from '@/server/scheduler';

const silent: Logger = { info: () => {}, warn: () => {}, error: () => {} };

describe('nextRunAt', () => {
  const MIN = 60_000;
  it('duvar saatine ve ofsete hizalanır, her zaman gelecekte kalır', () => {
    const t = Date.UTC(2026, 8, 28, 10, 7, 12);
    expect(new Date(nextRunAt(t, 5 * MIN, 30_000)).toISOString()).toBe('2026-09-28T10:10:30.000Z');
    const exact = Date.UTC(2026, 8, 28, 10, 10, 30);
    expect(nextRunAt(exact, 5 * MIN, 30_000)).toBe(exact + 5 * MIN);
  });
});

describe('job kilitleri', () => {
  it('aynı job paylaşılan kilit tutulurken ikinci kez çalışmaz', async () => {
    const cache = new MemoryCache();
    let release!: () => void;
    let runs = 0;
    const job = {
      name: 'yavas',
      everyMs: 60_000,
      run: () =>
        new Promise<void>((resolve) => {
          runs++;
          release = resolve;
        }),
    };
    const workerA = createJobRunner(job, { cache, log: silent });
    const workerB = createJobRunner(job, { cache, log: silent });

    const first = workerA({});
    await new Promise((r) => setTimeout(r, 0));
    expect(await workerA({})).toBe('skipped-running');
    expect(await workerB({})).toBe('skipped-locked');
    release();
    expect(await first).toBe('ok');
    expect(runs).toBe(1);

    // Kilit serbest bırakıldıktan sonra diğer kopya çalışabilir.
    const second = workerB({});
    await new Promise((r) => setTimeout(r, 0));
    release();
    expect(await second).toBe('ok');
  });

  it('hata veren job kilidi bırakır ve "failed" döner', async () => {
    const cache = new MemoryCache();
    const run = createJobRunner({ name: 'bozuk', everyMs: 1_000, run: async () => { throw new Error('x'); } }, { cache, log: silent });
    expect(await run({})).toBe('failed');
    expect(await cache.acquireLock('lock:job:bozuk', 1_000)).not.toBeNull();
  });
});
