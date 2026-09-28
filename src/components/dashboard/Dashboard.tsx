'use client';

import { TriangleAlert } from 'lucide-react';
import { useState } from 'react';
import type { HoursReport, Period, RankingsReport } from '@/lib/types';
import { ChainHours } from './ChainHours';
import { Header } from './Header';
import { PeriodLeaders } from './PeriodLeaders';
import { RankingTable } from './RankingTable';
import { useJson } from './useJson';

const RANKINGS_REFRESH_MS = 10 * 60_000;
const HOURS_REFRESH_MS = 15 * 60_000;

/**
 * Yerleşim: üstte gün/hafta/ay liderleri; altta solda chain sıralaması, sağda seçili
 * chain'in gün içi saat analizi. Telefonda tek sütuna iner.
 */
export function Dashboard({ initialRankings, initialError }: { initialRankings: RankingsReport | null; initialError: string | null }) {
  const rankings = useJson<RankingsReport>('/api/rankings', RANKINGS_REFRESH_MS, initialRankings, initialError);
  const [period, setPeriod] = useState<Period>('day');
  const [picked, setPicked] = useState<string | null>(null);

  const rows = rankings.data?.rows ?? [];
  const selected = picked ?? rows[0]?.chain ?? null;
  const hours = useJson<HoursReport>(selected ? `/api/hours?chain=${encodeURIComponent(selected)}` : null, HOURS_REFRESH_MS);

  const select = (chain: string) => {
    setPicked(chain);
    document.getElementById('saatler')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  return (
    <div className="mx-auto max-w-[1440px] px-4 pb-10 sm:px-6">
      <Header asOfDay={rankings.data?.asOfDay ?? null} stale={rankings.data?.stale ?? false} loading={rankings.loading} />

      {!rankings.data ? (
        <div className="rounded-xl border border-down/40 bg-panel p-6">
          <div className="flex items-start gap-3">
            <TriangleAlert className="mt-0.5 size-5 shrink-0 text-down" aria-hidden />
            <div>
              <h2 className="font-semibold text-ink">Chain verisi alınamadı</h2>
              <p className="mt-1 text-sm text-ink-2">{rankings.error ?? 'Bilinmeyen hata'}</p>
              <p className="mt-2 text-xs text-muted">
                Bu panel yalnızca gerçek veri gösterir. Sunucunun <code>api.llama.fi</code> ve{' '}
                <code>api.geckoterminal.com</code> adreslerine internet erişimi olmalı.
              </p>
              <button
                type="button"
                onClick={() => void rankings.reload()}
                className="mt-3 rounded-md border border-line px-3 py-1.5 text-xs text-ink-2 hover:bg-raised"
              >
                Tekrar dene
              </button>
            </div>
          </div>
        </div>
      ) : (
        <main className="flex flex-col gap-4">
          <PeriodLeaders rows={rows} asOfDay={rankings.data.asOfDay} onSelect={select} />
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-12">
            <div className="min-w-0 lg:col-span-5">
              <RankingTable report={rankings.data} period={period} onPeriod={setPeriod} selected={selected} onSelect={select} />
            </div>
            <div id="saatler" className="min-w-0 scroll-mt-4 lg:col-span-7">
              <ChainHours
                rows={rows}
                selected={selected}
                onSelect={setPicked}
                report={hours.data}
                error={hours.error}
                loading={hours.loading}
                onRetry={() => void hours.reload()}
              />
            </div>
          </div>
        </main>
      )}

      <footer className="mt-8 border-t border-line pt-4 text-[11px] leading-relaxed text-muted">
        Aktivite ölçüsü: DEX işlem hacmi (USD). Sıralama: DefiLlama günlük verisi; dönemler tamamlanmış UTC
        günlerinden oluşan kayan pencerelerdir (gün = son tam gün, hafta = son 7 gün, ay = son 30 gün). Saatler:
        GeckoTerminal, her chain'in en yüksek hacimli havuzlarının saatlik hacmi. Bu panel analitik amaçlıdır, yatırım
        tavsiyesi değildir.
      </footer>
    </div>
  );
}
