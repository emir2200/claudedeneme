import { NextResponse } from 'next/server';
import { getDashboardSnapshot } from '@/server/snapshot/getSnapshot';

export const dynamic = 'force-dynamic';

/** Dashboard'un tek veri uç noktası. İstemci 15 saniyede bir yoklar. */
export async function GET() {
  try {
    const snapshot = await getDashboardSnapshot();
    return NextResponse.json(snapshot, { headers: { 'Cache-Control': 'no-store' } });
  } catch (err) {
    console.error('dashboard snapshot alınamadı', err);
    return NextResponse.json({ error: 'Veri şu anda alınamıyor' }, { status: 503 });
  }
}
