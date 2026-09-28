import type { z } from 'zod';

/** Dakika başına istek sınırı için basit token bucket (süreç içi). */
export class RateLimiter {
  private tokens: number;
  private last = Date.now();

  constructor(private readonly perMinute: number) {
    this.tokens = perMinute;
  }

  async take(): Promise<void> {
    for (;;) {
      const now = Date.now();
      this.tokens = Math.min(this.perMinute, this.tokens + ((now - this.last) / 60_000) * this.perMinute);
      this.last = now;
      if (this.tokens >= 1) {
        this.tokens -= 1;
        return;
      }
      await sleep(Math.ceil(((1 - this.tokens) / this.perMinute) * 60_000));
    }
  }
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly url: string,
  ) {
    super(`HTTP ${status}: ${url}`);
  }
}

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export interface FetchJsonOptions<S extends z.ZodType> {
  schema: S;
  headers?: Record<string, string>;
  limiter?: RateLimiter;
  retries?: number;
  timeoutMs?: number;
}

/**
 * JSON GET + şema doğrulaması. 429 ve 5xx yanıtlarında `Retry-After` başlığına uyarak
 * üstel geri çekilmeyle yeniden dener. Şema uyuşmazlığında sessizce devam etmek yerine
 * hata fırlatır: sağlayıcı yanıt biçimini değiştirirse bunu log'da hemen görürüz.
 */
export async function fetchJson<S extends z.ZodType>(url: string, options: FetchJsonOptions<S>): Promise<z.infer<S>> {
  const { schema, headers, limiter, retries = 3, timeoutMs = 15_000 } = options;
  for (let attempt = 0; ; attempt++) {
    await limiter?.take();
    let res: Response;
    try {
      res = await fetch(url, {
        headers: { accept: 'application/json', ...headers },
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err) {
      if (attempt >= retries) throw err;
      await sleep(backoff(attempt));
      continue;
    }
    if (res.status === 429 || res.status >= 500) {
      if (attempt >= retries) throw new HttpError(res.status, url);
      const retryAfter = Number(res.headers.get('retry-after'));
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : backoff(attempt));
      continue;
    }
    if (!res.ok) throw new HttpError(res.status, url);
    return schema.parse(await res.json());
  }
}

function backoff(attempt: number): number {
  return Math.min(30_000, 1_000 * 2 ** attempt) + Math.floor(Math.random() * 250);
}
