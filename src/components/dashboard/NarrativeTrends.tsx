import { Megaphone, TrendingUp } from 'lucide-react';
import { formatNumber, formatUsd } from '@/lib/format';
import type { NarrativeTrend } from '@/lib/types';
import { Delta } from '../ui/Delta';
import { Meter } from '../ui/Meter';
import { Panel } from '../ui/Panel';
import { Sparkline } from '../ui/Sparkline';

const ACCENT = '#38bdf8';
const MUTED_LINE = '#7d8494';

export function NarrativeTrends({ narratives, rising }: { narratives: NarrativeTrend[]; rising: NarrativeTrend | null }) {
  return (
    <Panel
      title="Narrative Trendleri"
      icon={Megaphone}
      subtitle="Momentum = mention büyümesi (%35) + yeni token büyümesi (%25) + hacim payı (%25) + fiyat ivmesi (%15)"
    >
      {rising ? (
        <div className="rounded-lg border border-accent/30 bg-accent/5 p-3">
          <div className="flex items-center gap-1.5 text-[11px] font-semibold tracking-wide text-accent uppercase">
            <TrendingUp className="size-3.5" aria-hidden />
            Günün en hızlı yükselen narrative’i
          </div>
          <div className="mt-1 flex flex-wrap items-end justify-between gap-3">
            <div>
              <div className="text-xl font-semibold text-ink">{rising.name}</div>
              <div className="mt-0.5 flex flex-wrap items-center gap-x-3 text-xs text-muted">
                <span>
                  mention <Delta value={rising.mentionGrowthPct} digits={0} className="text-xs" />
                </span>
                <span>
                  hacim <span className="text-ink-2">{formatUsd(rising.volume24hUsd)}</span>
                </span>
                <span>
                  yeni token <span className="text-ink-2">{rising.newTokens24h}</span>
                </span>
              </div>
            </div>
            <div className="text-right">
              <div className="text-2xl leading-none font-semibold text-ink">{rising.momentum}</div>
              <div className="text-[11px] text-muted">momentum /100</div>
            </div>
          </div>
          {rising.topSymbols.length ? (
            <div className="mt-2 flex flex-wrap gap-1">
              {rising.topSymbols.map((s) => (
                <span key={s} className="rounded border border-line bg-panel px-1.5 py-0.5 font-mono text-[11px] text-ink-2">
                  ${s}
                </span>
              ))}
            </div>
          ) : null}
        </div>
      ) : null}

      <div className="mt-3 overflow-x-auto">
        <table className="w-full text-xs">
          <caption className="sr-only">Narrative momentum sıralaması</caption>
          <thead className="text-[11px] text-muted">
            <tr className="border-b border-line">
              <th className="py-1.5 pr-2 text-left font-medium">Narrative</th>
              <th className="w-20 py-1.5 pr-2 text-left font-medium sm:w-28">Momentum</th>
              <th className="py-1.5 pr-2 text-right font-medium">Mention 24s</th>
              <th className="py-1.5 pr-2 text-right font-medium">Hacim 24s</th>
              <th className="hidden py-1.5 text-right font-medium sm:table-cell">Mention eğrisi</th>
            </tr>
          </thead>
          <tbody>
            {narratives.map((n, i) => (
              <tr key={n.slug} className="border-b border-line/60 last:border-0">
                <td className="py-2 pr-2">
                  <div className="font-medium text-ink">
                    <span className="mr-1.5 text-muted tabular">{i + 1}.</span>
                    {n.name}
                  </div>
                  <div className="text-[11px] text-muted">
                    {n.tokenCount} token · pay %{Math.round(n.volumeShare * 100)}
                  </div>
                </td>
                <td className="py-2 pr-2">
                  <div className="flex items-center gap-2">
                    <Meter value={n.momentum} color={ACCENT} label={`${n.name} momentum`} />
                    <span className="w-6 text-right font-semibold text-ink tabular">{n.momentum}</span>
                  </div>
                </td>
                <td className="py-2 pr-2 text-right">
                  <div className="text-ink tabular">{formatNumber(n.mentions24h)}</div>
                  <Delta value={n.mentionGrowthPct} digits={0} className="text-[11px]" />
                </td>
                <td className="py-2 pr-2 text-right text-ink-2 tabular">{formatUsd(n.volume24hUsd)}</td>
                <td className="hidden py-2 text-right sm:table-cell">
                  <div className="flex justify-end">
                    <Sparkline
                      values={n.mentionSeries}
                      color={i === 0 ? ACCENT : MUTED_LINE}
                      width={84}
                      height={24}
                      label={`${n.name} son 24 saat saatlik mention`}
                    />
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Panel>
  );
}
