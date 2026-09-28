// Süreç içi önbellek: TTL + eşzamanlı isteklerin tek çağrıda birleşmesi + kaynak
// hata verirse eski veriyi "bayat" işaretiyle sunma. Tek sunucu için yeterlidir.

interface Entry<T> {
  value: T;
  at: number;
}

const entries = new Map<string, Entry<unknown>>();
const inflight = new Map<string, Promise<unknown>>();

export async function cached<T>(key: string, ttlMs: number, load: () => Promise<T>): Promise<{ value: T; stale: boolean }> {
  const hit = entries.get(key) as Entry<T> | undefined;
  if (hit && Date.now() - hit.at < ttlMs) return { value: hit.value, stale: false };

  let pending = inflight.get(key) as Promise<T> | undefined;
  if (!pending) {
    pending = load().finally(() => inflight.delete(key));
    inflight.set(key, pending);
  }
  try {
    const value = await pending;
    entries.set(key, { value, at: Date.now() });
    return { value, stale: false };
  } catch (err) {
    if (hit) return { value: hit.value, stale: true };
    throw err;
  }
}

/** Testler için. */
export function clearCache() {
  entries.clear();
  inflight.clear();
}
