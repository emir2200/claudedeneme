import { NextResponse, type NextRequest } from 'next/server';
import { describeError, getHours, UnknownChainError } from '@/server/reports';

export const dynamic = 'force-dynamic';

/** Bir chain'in gün içindeki en aktif trade saatleri: /api/hours?chain=solana */
export async function GET(request: NextRequest) {
  const chain = request.nextUrl.searchParams.get('chain') ?? '';
  try {
    return NextResponse.json(await getHours(chain), { headers: { 'Cache-Control': 'no-store' } });
  } catch (err) {
    const status = err instanceof UnknownChainError ? 400 : 502;
    return NextResponse.json({ error: describeError(err) }, { status });
  }
}
