import { Crown, TriangleAlert } from 'lucide-react';
import { LAUNCHPAD_NAMES } from '@/lib/analytics/launchpads';
import { DEFAULT_HYPE_FILTERS, RISK_FLAG_TEXT } from '@/lib/analytics/hype';
import { NARRATIVE_BY_SLUG } from '@/lib/analytics/narratives';
import { CHAINS } from '@/lib/chains';
import { formatNumber, formatPrice, formatRatio, formatUsd } from '@/lib/format';
import type { HypeToken } from '@/lib/types';
import { ChainBadge, ChainTag } from '../ui/ChainBadge';
import { ContractAddress } from '../ui/ContractAddress';
import { Delta } from '../ui/Delta';
import { Meter } from '../ui/Meter';
import { Panel } from '../ui/Panel';
import { Sparkline } from '../ui/Sparkline';

const ACCENT = '#38bdf8';

function Metric({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="min-w-0 rounded-md bg-raised/50 px-2 py-1.5" title={hint}>
      <div className="truncate text-[11px] text-muted">{label}</div>
      <div className="truncate text-sm font-semibold text-ink">{value}</div>
    </div>
  );
}

function age(hours: number | null) {
  if (hours === null) return null;
  return hours < 48 ? `${Math.round(hours)} sa` : `${Math.round(hours / 24)} gün`;
}

export function CoinOfTheDay({ coin, leaders, demo }: { coin: HypeToken | null; leaders: HypeToken[]; demo: boolean }) {
  return (
    <Panel
      title="Günün Coin’i"
      icon={Crown}
      subtitle="Sosyal hype × on-chain doğrulama: etkileşim, mention hızı, Vol/MCap ve fiyat ivmesi"
    >
      {!coin ? (
        <p className="text-sm text-muted">
          Eşikleri (likidite ≥ {formatUsd(DEFAULT_HYPE_FILTERS.minLiquidityUsd)}, MCap ≥{' '}
          {formatUsd(DEFAULT_HYPE_FILTERS.minMarketCapUsd)}) geçen aday yok.
        </p>
      ) : (
        <>
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <ChainBadge chain={coin.chain} />
                <span className="text-[11px] text-muted">
                  {LAUNCHPAD_NAMES[coin.launchpad]}
                  {coin.ageHours !== null ? ` · ${age(coin.ageHours)}` : ''}
                </span>
              </div>
              <div className="mt-1 truncate font-mono text-2xl font-semibold text-ink">${coin.symbol}</div>
              <div className="truncate text-xs text-muted">{coin.name}</div>
            </div>
            <div className="shrink-0 text-right">
              <div className="text-[11px] text-muted">Hype skoru</div>
              <div className="text-5xl leading-none font-semibold text-ink">{coin.hypeScore}</div>
            </div>
          </div>
          <ContractAddress chain={coin.chain} address={coin.address} symbol={coin.symbol} demo={demo} />
          <Meter value={coin.hypeScore} color={ACCENT} label="Hype skoru" className="mt-3" />

          <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
            <span className="font-semibold text-ink">{formatPrice(coin.priceUsd)}</span>
            <Delta value={coin.priceChange24hPct} />
            <span className="text-xs text-muted">24s</span>
            {coin.narratives.map((n) => (
              <span key={n} className="rounded border border-line px-1.5 py-0.5 text-[11px] text-ink-2">
                {NARRATIVE_BY_SLUG.get(n)?.name ?? n}
              </span>
            ))}
          </div>

          <div className="mt-3 grid grid-cols-2 gap-1.5">
            <Metric label="Sosyal hacim (24s)" value={`${formatNumber(coin.mentions24h)} mention`} />
            <Metric label="Etkileşim (24s)" value={formatNumber(coin.engagements24h)} />
            <Metric label="Mention hızı" value={formatRatio(coin.mentionVelocity, 1)} hint="Son 24 saat / önceki 24 saat" />
            <Metric label="Vol / MCap" value={formatRatio(coin.volMcapRatio)} hint="24s hacim / piyasa değeri (devir hızı)" />
            <Metric label="Sosyal / Likidite" value={formatNumber(Math.round(coin.socialToLiquidity))} hint="$1K likidite başına etkileşim" />
            <Metric label="Duygu" value={coin.sentiment === null ? '—' : `%${Math.round(coin.sentiment * 100)} olumlu`} />
            <Metric label="Piyasa değeri" value={formatUsd(coin.marketCapUsd)} />
            <Metric label="Likidite" value={formatUsd(coin.liquidityUsd)} />
          </div>

          <div className="mt-3 flex items-center justify-between gap-3 rounded-md bg-raised/40 px-2.5 py-1.5">
            <span className="text-[11px] text-muted">Saatlik mention · 24s</span>
            <Sparkline values={coin.mentionSeries} color={ACCENT} width={140} height={28} label={`$${coin.symbol} son 24 saat saatlik mention`} />
          </div>

          {coin.riskFlags.length ? (
            <ul className="mt-2 space-y-1">
              {coin.riskFlags.map((f) => (
                <li key={f} className="flex items-center gap-1.5 text-[11px] text-warn">
                  <TriangleAlert className="size-3.5 shrink-0" aria-hidden />
                  <span>Risk: {RISK_FLAG_TEXT[f]}</span>
                </li>
              ))}
            </ul>
          ) : null}
        </>
      )}

      {leaders.length > 1 ? (
        <div className="mt-4">
          <h3 className="mb-1.5 text-[11px] font-semibold tracking-wide text-muted uppercase">Hype liderleri</h3>
          <ol className="space-y-1">
            {leaders.map((t, i) => (
              <li key={`${t.chain}:${t.address}`} className="grid grid-cols-[1rem_minmax(0,1fr)_3.5rem_1.75rem] items-center gap-2 text-xs">
                <span className="text-muted tabular">{i + 1}</span>
                <span className="flex min-w-0 items-center gap-1.5">
                  <ChainTag chain={t.chain} />
                  <span className="truncate font-mono text-ink">${t.symbol}</span>
                  {t.riskFlags.includes('asiri-devir') ? (
                    <TriangleAlert className="size-3 shrink-0 text-warn" aria-label="Aşırı devir" />
                  ) : null}
                </span>
                <Delta value={t.priceChange24hPct} digits={0} className="justify-end text-[11px]" />
                <span className="text-right font-semibold text-ink tabular" title={`${CHAINS[t.chain].name} · hype ${t.hypeScore}`}>
                  {t.hypeScore}
                </span>
              </li>
            ))}
          </ol>
          {leaders.some((t) => t.riskFlags.includes('asiri-devir')) ? (
            <p className="mt-1.5 flex items-center gap-1 text-[11px] text-muted">
              <TriangleAlert className="size-3 text-warn" aria-hidden />
              Aşırı devir (olası wash-trade): Günün Coin’i seçilemez.
            </p>
          ) : null}
        </div>
      ) : null}
    </Panel>
  );
}
