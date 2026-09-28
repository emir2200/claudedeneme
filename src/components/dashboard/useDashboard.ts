'use client';

import { useEffect, useState } from 'react';
import type { DashboardSnapshot } from '@/lib/types';

export type FetchStatus = 'idle' | 'loading' | 'error';

/**
 * Snapshot'ı periyodik olarak yeniler. Yenileme sırasında önceki veri ekranda kalır
 * (iskelet/zıplama yok); sekme gizliyken istek atılmaz.
 */
export function useDashboard(initial: DashboardSnapshot, intervalMs = 15_000) {
  const [data, setData] = useState(initial);
  const [status, setStatus] = useState<FetchStatus>('idle');

  useEffect(() => {
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;

    const tick = async () => {
      if (document.visibilityState === 'visible') {
        setStatus('loading');
        try {
          const res = await fetch('/api/dashboard', { cache: 'no-store' });
          if (!res.ok) throw new Error(String(res.status));
          const next = (await res.json()) as DashboardSnapshot;
          if (!cancelled) {
            setData(next);
            setStatus('idle');
          }
        } catch {
          if (!cancelled) setStatus('error');
        }
      }
      if (!cancelled) timer = setTimeout(tick, intervalMs);
    };

    timer = setTimeout(tick, intervalMs);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [intervalMs]);

  return { data, status };
}
