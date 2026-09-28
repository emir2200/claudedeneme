'use client';

import { Radar, RefreshCw, TriangleAlert } from 'lucide-react';
import { useEffect, useState } from 'react';
import { shortDate } from '@/lib/format';

function useClock() {
  const [now, setNow] = useState<Date | null>(null);
  useEffect(() => {
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), 1_000);
    return () => clearInterval(id);
  }, []);
  return now;
}

export function Header({ asOfDay, stale, loading }: { asOfDay: string | null; stale: boolean; loading: boolean }) {
  const now = useClock();
  return (
    <header className="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 pt-5 pb-4">
      <div className="flex items-center gap-3">
        <div className="grid size-10 place-items-center rounded-lg border border-accent/30 bg-accent/10">
          <Radar className="size-5 text-accent" aria-hidden />
        </div>
        <div>
          <h1 className="text-lg font-semibold tracking-tight text-ink sm:text-xl">Chain Aktivite Radarı</h1>
          <p className="text-xs text-muted">Günün, haftanın ve ayın en aktif chain’leri · gün içindeki en aktif trade saatleri</p>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2 text-xs">
        {stale ? (
          <span className="inline-flex items-center gap-1.5 rounded-md border border-warn/40 bg-warn/10 px-2 py-1 text-warn">
            <TriangleAlert className="size-3.5" aria-hidden />
            Kaynak yanıt vermiyor, son alınan veri gösteriliyor
          </span>
        ) : null}
        <span className="inline-flex items-center gap-1.5 rounded-md border border-line px-2 py-1 text-muted">
          <RefreshCw className={`size-3.5 ${loading ? 'animate-spin text-accent' : ''}`} aria-hidden />
          Son tam gün <span className="text-ink-2">{asOfDay ? `${shortDate(asOfDay)} (UTC)` : '—'}</span>
        </span>
        <span className="tabular hidden rounded-md border border-line px-2 py-1 text-ink-2 sm:inline" suppressHydrationWarning>
          {now ? `${now.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })} yerel` : '—'}
        </span>
      </div>
    </header>
  );
}
