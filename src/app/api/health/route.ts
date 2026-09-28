import { NextResponse } from 'next/server';
import { CACHE_KEYS, getCache } from '@/server/cache';
import { getConfig } from '@/server/config';
import { getPrisma } from '@/server/db';

export const dynamic = 'force-dynamic';

/** Canlılık/hazırlık kontrolü: mod, veritabanı, Redis ve snapshot yaşı. */
export async function GET() {
  const config = getConfig();
  if (config.DATA_MODE === 'demo') return NextResponse.json({ ok: true, mode: 'demo' });

  const checks: Record<string, unknown> = { mode: 'live' };
  try {
    await getPrisma().$queryRaw`SELECT 1`;
    checks.database = 'ok';
  } catch {
    checks.database = 'hata';
  }
  const cache = getCache();
  checks.redis = (await cache.ping()) ? 'ok' : 'hata';
  const raw = await cache.get(CACHE_KEYS.snapshot).catch(() => null);
  const generatedAt = raw ? (JSON.parse(raw) as { generatedAt?: string }).generatedAt : undefined;
  checks.snapshotAgeSec = generatedAt ? Math.round((Date.now() - Date.parse(generatedAt)) / 1000) : null;

  const ok = checks.database === 'ok' && checks.redis === 'ok';
  return NextResponse.json({ ok, ...checks }, { status: ok ? 200 : 503 });
}
