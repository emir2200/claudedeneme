import { NextResponse } from 'next/server';
import { describeError, getRankings } from '@/server/reports';

export const dynamic = 'force-dynamic';

/** Günün, haftanın ve ayın chain sıralaması. */
export async function GET() {
  try {
    return NextResponse.json(await getRankings(), { headers: { 'Cache-Control': 'no-store' } });
  } catch (err) {
    return NextResponse.json({ error: describeError(err) }, { status: 502 });
  }
}
