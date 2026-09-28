'use client';

import { Info, Radar, RefreshCw, WifiOff } from 'lucide-react';
import { useEffect, useState } from 'react';
import { CHAIN_LIST } from '@/lib/chains';
import type { DataMode } from '@/lib/types';
import type { FetchStatus } from './useDashboard';

function useClock() {
  const [now, setNow] = useState<Date | null>(null);
  useEffect(() => {
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), 1_000);
    return () => clearInterval(id);
  }, []);
  return now;
}

const timeFmt = (d: Date, timeZone?: string) =>
  d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit', timeZone });

export function Header({ mode, generatedAt, status }: { mode: DataMode; generatedAt: string; status: FetchStatus }) {
  const now = useClock();
  return (
    <header className="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 pt-5 pb-3">
      <div className="flex items-center gap-3">
        <div className="grid size-10 place-items-center rounded-lg border border-accent/30 bg-accent/10">
          <Radar className="size-5 text-accent" aria-hidden />
        </div>
        <div>
          <h1 className="text-lg font-semibold tracking-tight text-ink sm:text-xl">Memecoin Haritası</h1>
          <p className="text-xs text-muted">
            {CHAIN_LIST.map((c) => c.name).join(' · ')} — sıcak para nereye akıyor?
          </p>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2 text-xs">
        {mode === 'demo' ? (
          <span
            className="inline-flex items-center gap-1.5 rounded-md border border-warn/40 bg-warn/10 px-2 py-1 font-semibold text-warn"
            title="API anahtarı olmadan çalışan simülasyon verisi. Canlı veri için DATA_MODE=live."
          >
            <Info className="size-3.5" aria-hidden />
            DEMO VERİ · simülasyon
          </span>
        ) : (
          <span className="inline-flex items-center gap-1.5 rounded-md border border-up/40 bg-up/10 px-2 py-1 font-semibold text-up">
            <span className="live-dot size-2 rounded-full bg-up" aria-hidden />
            CANLI
          </span>
        )}
        {status === 'error' ? (
          <span className="inline-flex items-center gap-1.5 rounded-md border border-down/40 px-2 py-1 text-down">
            <WifiOff className="size-3.5" aria-hidden />
            Bağlantı sorunu — son veri gösteriliyor
          </span>
        ) : null}
        <span className="inline-flex items-center gap-1.5 rounded-md border border-line px-2 py-1 text-muted">
          <RefreshCw className={`size-3.5 ${status === 'loading' ? 'animate-spin text-accent' : ''}`} aria-hidden />
          <span>
            Güncelleme <span className="tabular text-ink-2">{timeFmt(new Date(generatedAt), 'UTC')}</span> UTC
          </span>
        </span>
        <span className="tabular hidden rounded-md border border-line px-2 py-1 text-ink-2 sm:inline" suppressHydrationWarning>
          {now ? `${timeFmt(now)} yerel` : '—'}
        </span>
      </div>
    </header>
  );
}
