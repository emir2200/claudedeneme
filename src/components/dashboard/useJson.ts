'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

export interface JsonState<T> {
  data: T | null;
  error: string | null;
  loading: boolean;
}

/**
 * Bir API ucunu yükler ve `intervalMs` aralıklarla yeniler. Yenileme sırasında önceki veri
 * ekranda kalır; sekme gizliyken istek atılmaz. `url` null ise hiçbir şey yapmaz.
 */
export function useJson<T>(url: string | null, intervalMs: number, initial: T | null = null, initialError: string | null = null) {
  const [state, setState] = useState<JsonState<T>>({ data: initial, error: initialError, loading: false });
  const skipFirst = useRef(initial !== null || initialError !== null);

  const load = useCallback(async () => {
    if (!url) return;
    setState((s) => ({ ...s, loading: true }));
    try {
      const res = await fetch(url, { cache: 'no-store' });
      const body = (await res.json()) as T | { error: string };
      if (!res.ok || (body && typeof body === 'object' && 'error' in body)) {
        throw new Error((body as { error?: string }).error ?? `HTTP ${res.status}`);
      }
      setState({ data: body as T, error: null, loading: false });
    } catch (err) {
      setState((s) => ({ ...s, error: err instanceof Error ? err.message : String(err), loading: false }));
    }
  }, [url]);

  useEffect(() => {
    if (!url) return;
    if (skipFirst.current) skipFirst.current = false;
    else void load();
    const id = setInterval(() => {
      if (document.visibilityState === 'visible') void load();
    }, intervalMs);
    return () => clearInterval(id);
  }, [url, intervalMs, load]);

  return { ...state, reload: load };
}
