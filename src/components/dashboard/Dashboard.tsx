'use client';

import type { DashboardSnapshot } from '@/lib/types';
import { ChainHeatmap } from './ChainHeatmap';
import { CoinOfTheDay } from './CoinOfTheDay';
import { Header } from './Header';
import { LaunchMeter } from './LaunchMeter';
import { NarrativeTrends } from './NarrativeTrends';
import { TickerBanner } from './TickerBanner';
import { TradeTimeMatrix } from './TradeTimeMatrix';
import { useDashboard } from './useDashboard';
import { WhaleFeed } from './WhaleFeed';

/**
 * Yerleşim (masaüstü): üstte canlı ticker; sol: zincir ısı haritası + 100K sayacı;
 * orta: trade zamanı matrisi + narrative trendleri; sağ: günün coini + balina akışı.
 * Tablet'te iki, telefonda tek sütuna iner.
 */
export function Dashboard({ initial }: { initial: DashboardSnapshot }) {
  const { data, status } = useDashboard(initial);

  return (
    <div className="mx-auto max-w-[1680px] px-4 pb-10 sm:px-6">
      <Header mode={data.mode} generatedAt={data.generatedAt} status={status} />
      <TickerBanner items={data.ticker} narrative={data.risingNarrative} />

      <main className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2 xl:grid-cols-12">
        <div className="flex min-w-0 flex-col gap-4 xl:col-span-4">
          <ChainHeatmap chains={data.chains} />
          <LaunchMeter report={data.launches} />
        </div>
        <div className="flex min-w-0 flex-col gap-4 xl:col-span-5">
          <TradeTimeMatrix report={data.trade} generatedAt={data.generatedAt} />
          <NarrativeTrends narratives={data.narratives} rising={data.risingNarrative} />
        </div>
        <div className="flex min-w-0 flex-col gap-4 lg:col-span-2 lg:grid lg:grid-cols-2 xl:col-span-3 xl:flex">
          <CoinOfTheDay coin={data.coinOfTheDay} leaders={data.hypeLeaders} demo={data.mode === 'demo'} />
          <WhaleFeed report={data.whales} generatedAt={data.generatedAt} demo={data.mode === 'demo'} />
        </div>
      </main>

      <footer className="mt-8 border-t border-line pt-4 text-[11px] leading-relaxed text-muted">
        Veri kaynakları: DEXScreener, GeckoTerminal, DefiLlama, LunarCrush, Helius, zincir RPC’leri. Tüm saatler aksi
        belirtilmedikçe UTC’dir; günlük sayaçlar UTC gün sınırına göre sıfırlanır. Bu panel analitik amaçlıdır,
        yatırım tavsiyesi değildir.
      </footer>
    </div>
  );
}
