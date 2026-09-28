// Helius "enhanced transaction" webhook'u → Solana balina swapları ve bot/insan sayaçları.
// Helius panelinde webhook türü "enhanced", hesap listesi takip edilen token mint'leri,
// "Authorization header" alanı HELIUS_WEBHOOK_SECRET olmalıdır.

import { timingSafeEqual } from 'node:crypto';
import { NextResponse } from 'next/server';
import { getCache } from '@/server/cache';
import { getConfig } from '@/server/config';
import { getPrisma } from '@/server/db';
import { recentActivity, recordWalletActivity, recordWhaleTrades } from '@/server/ingest/swaps';
import { heliusPayloadSchema, parseHeliusSwaps, type TrackedMint } from '@/server/providers/helius';

export const dynamic = 'force-dynamic';

function authorized(header: string | null, secret: string): boolean {
  if (!header) return false;
  const a = Buffer.from(header);
  const b = Buffer.from(secret);
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function POST(request: Request) {
  const config = getConfig();
  if (!config.HELIUS_WEBHOOK_SECRET || config.DATA_MODE !== 'live') {
    return NextResponse.json({ error: 'Webhook devre dışı' }, { status: 503 });
  }
  if (!authorized(request.headers.get('authorization'), config.HELIUS_WEBHOOK_SECRET)) {
    return NextResponse.json({ error: 'Yetkisiz' }, { status: 401 });
  }

  const parsed = heliusPayloadSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: 'Geçersiz yük' }, { status: 400 });

  const prisma = getPrisma();
  const mints = [...new Set(parsed.data.flatMap((tx) => (tx.tokenTransfers ?? []).map((t) => t.mint)))];
  const tokens = await prisma.token.findMany({
    where: { chain: 'SOLANA', address: { in: mints }, priceUsd: { gt: 0 } },
    select: { address: true, symbol: true, priceUsd: true },
  });
  const tracked = new Map<string, TrackedMint>(tokens.map((t) => [t.address, { symbol: t.symbol, priceUsd: t.priceUsd! }]));

  const swaps = parseHeliusSwaps(parsed.data, tracked);
  const cache = getCache();
  await recordWalletActivity(cache, 'solana', recentActivity(swaps, new Date()));
  const whales = await recordWhaleTrades({ prisma, cache, whaleMinUsd: config.WHALE_MIN_USD }, 'solana', swaps);

  return NextResponse.json({ ok: true, swaps: swaps.length, whales });
}
