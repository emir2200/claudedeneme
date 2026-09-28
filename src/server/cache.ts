// Önbellek katmanı: REDIS_URL varsa Redis, yoksa süreç içi bellek.
// Bellek sürümü tek süreçli geliştirme içindir; birden çok worker/web kopyası çalışıyorsa
// kilitlerin ve sayaçların paylaşılması için Redis zorunludur.

import { randomUUID } from 'node:crypto';
import Redis from 'ioredis';
import type { ChainId } from '@/lib/chains';
import { getConfig } from './config';

export const CACHE_KEYS = {
  snapshot: 'dash:snapshot:v1',
  snapshotLock: 'lock:dash:snapshot',
  llamaContext: 'provider:llama:context',
  jobLock: (name: string) => `lock:job:${name}`,
  /** Saatlik cüzdan → swap sayısı (bot/insan ayrımı için). */
  walletCounter: (chain: ChainId, hourStart: Date) => `swaps:${chain}:${hourStart.getTime()}`,
} as const;

export interface Cache {
  get(key: string): Promise<string | null>;
  set(key: string, value: string, ttlSec: number): Promise<void>;
  del(key: string): Promise<void>;
  /** Başarılıysa kilidi serbest bırakmak için gereken jetonu döner. */
  acquireLock(key: string, ttlMs: number): Promise<string | null>;
  releaseLock(key: string, token: string): Promise<void>;
  incrementFields(key: string, increments: ReadonlyMap<string, number>, ttlSec: number): Promise<void>;
  getFields(key: string): Promise<Record<string, number>>;
  ping(): Promise<boolean>;
  close(): Promise<void>;
}

const RELEASE_SCRIPT = `if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end`;

class RedisCache implements Cache {
  constructor(private readonly redis: Redis) {}

  get(key: string) {
    return this.redis.get(key);
  }
  async set(key: string, value: string, ttlSec: number) {
    await this.redis.set(key, value, 'EX', ttlSec);
  }
  async del(key: string) {
    await this.redis.del(key);
  }
  async acquireLock(key: string, ttlMs: number) {
    const token = randomUUID();
    const ok = await this.redis.set(key, token, 'PX', ttlMs, 'NX');
    return ok === 'OK' ? token : null;
  }
  async releaseLock(key: string, token: string) {
    await this.redis.eval(RELEASE_SCRIPT, 1, key, token);
  }
  async incrementFields(key: string, increments: ReadonlyMap<string, number>, ttlSec: number) {
    if (increments.size === 0) return;
    const pipeline = this.redis.pipeline();
    for (const [field, by] of increments) pipeline.hincrby(key, field, by);
    pipeline.expire(key, ttlSec);
    await pipeline.exec();
  }
  async getFields(key: string) {
    const raw = await this.redis.hgetall(key);
    return Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, Number(v)]));
  }
  async ping() {
    try {
      return (await this.redis.ping()) === 'PONG';
    } catch {
      return false;
    }
  }
  async close() {
    await this.redis.quit();
  }
}

export class MemoryCache implements Cache {
  private values = new Map<string, { value: string; expiresAt: number }>();
  private hashes = new Map<string, { fields: Map<string, number>; expiresAt: number }>();

  private alive<T extends { expiresAt: number }>(map: Map<string, T>, key: string): T | undefined {
    const entry = map.get(key);
    if (entry && entry.expiresAt <= Date.now()) {
      map.delete(key);
      return undefined;
    }
    return entry;
  }

  async get(key: string) {
    return this.alive(this.values, key)?.value ?? null;
  }
  async set(key: string, value: string, ttlSec: number) {
    this.values.set(key, { value, expiresAt: Date.now() + ttlSec * 1000 });
  }
  async del(key: string) {
    this.values.delete(key);
    this.hashes.delete(key);
  }
  async acquireLock(key: string, ttlMs: number) {
    if (this.alive(this.values, key)) return null;
    const token = randomUUID();
    this.values.set(key, { value: token, expiresAt: Date.now() + ttlMs });
    return token;
  }
  async releaseLock(key: string, token: string) {
    if (this.alive(this.values, key)?.value === token) this.values.delete(key);
  }
  async incrementFields(key: string, increments: ReadonlyMap<string, number>, ttlSec: number) {
    const entry = this.alive(this.hashes, key) ?? { fields: new Map<string, number>(), expiresAt: 0 };
    for (const [field, by] of increments) entry.fields.set(field, (entry.fields.get(field) ?? 0) + by);
    entry.expiresAt = Date.now() + ttlSec * 1000;
    this.hashes.set(key, entry);
  }
  async getFields(key: string) {
    return Object.fromEntries(this.alive(this.hashes, key)?.fields ?? []);
  }
  async ping() {
    return true;
  }
  async close() {}
}

const globalForCache = globalThis as unknown as { cache?: Cache };

export function getCache(): Cache {
  if (!globalForCache.cache) {
    const url = getConfig().REDIS_URL;
    globalForCache.cache = url
      ? new RedisCache(new Redis(url, { maxRetriesPerRequest: 2, lazyConnect: false }))
      : new MemoryCache();
  }
  return globalForCache.cache;
}
