'use client';

import { ListOrdered } from 'lucide-react';
import { formatUsd } from '@/lib/format';
import type { ChainRanking, Period, RankingsReport } from '@/lib/types';
import { Delta } from '../ui/Delta';
import { Meter } from '../ui/Meter';
import { Panel } from '../ui/Panel';
import { SegmentedControl } from '../ui/SegmentedControl';
import { Sparkline } from '../ui/Sparkline';

const ACCENT = '#38bdf8';
const MUTED_LINE = '#7d8494';

const PERIOD_OPTIONS = [
  { value: 'day', label: 'Gün' },
  { value: 'week', label: 'Hafta' },
  { value: 'month', label: 'Ay' },
] as const;

const PERIOD_HINT: Record<Period, string> = {
  day: 'son tam gün, önceki güne göre değişim',
  week: 'son 7 gün, önceki 7 güne göre değişim',
  month: 'son 30 gün, önceki 30 güne göre değişim',
};

export function RankingTable({
  report,
  period,
  onPeriod,
  selected,
  onSelect,
}: {
  report: RankingsReport;
  period: Period;
  onPeriod: (p: Period) => void;
  selected: string | null;
  onSelect: (chain: string) => void;
}) {
  const rows: ChainRanking[] = [...report.rows].sort((a, b) => a.stats[period].rank - b.stats[period].rank);
  const maxShare = Math.max(...rows.map((r) => r.stats[period].share), 0.0001);

  return (
    <Panel
      title="Chain sıralaması"
      icon={ListOrdered}
      subtitle={`Tüm DEX'lerdeki toplam işlem hacmi (DefiLlama) · ${PERIOD_HINT[period]}`}
      actions={<SegmentedControl label="Dönem" value={period} onChange={onPeriod} options={PERIOD_OPTIONS} />}
    >
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <caption className="sr-only">Chain'lerin {PERIOD_HINT[period]} DEX hacmine göre sıralaması</caption>
          <thead className="text-[11px] text-muted">
            <tr className="border-b border-line">
              <th className="py-1.5 pr-2 text-left font-medium">#</th>
              <th className="py-1.5 pr-2 text-left font-medium">Chain</th>
              <th className="py-1.5 pr-2 text-right font-medium">Hacim</th>
              <th className="hidden w-24 py-1.5 pr-2 text-left font-medium sm:table-cell">Pay</th>
              <th className="py-1.5 pr-2 text-right font-medium">Değişim</th>
              <th className="hidden py-1.5 text-right font-medium sm:table-cell">30 gün</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const s = r.stats[period];
              const isSelected = r.chain === selected;
              return (
                <tr
                  key={r.chain}
                  className={`border-b border-line/60 last:border-0 ${isSelected ? 'bg-accent/10' : 'hover:bg-raised/60'}`}
                >
                  <td className="py-2 pr-2 text-muted tabular">{s.rank}</td>
                  <td className="py-2 pr-2">
                    <button
                      type="button"
                      onClick={() => onSelect(r.chain)}
                      aria-pressed={isSelected}
                      className="text-left font-medium text-ink hover:text-accent"
                      title="Gün içi saatlerini göster"
                    >
                      {r.name}
                    </button>
                  </td>
                  <td className="py-2 pr-2 text-right font-semibold text-ink tabular">{formatUsd(s.volumeUsd)}</td>
                  <td className="hidden py-2 pr-2 sm:table-cell">
                    <div className="flex items-center gap-2">
                      <Meter value={(s.share / maxShare) * 100} color={ACCENT} label={`${r.name} pay`} />
                      <span className="w-8 text-right text-ink-2 tabular">%{Math.round(s.share * 100)}</span>
                    </div>
                  </td>
                  <td className="py-2 pr-2 text-right">
                    <Delta value={s.changePct} digits={0} className="justify-end text-[11px]" />
                  </td>
                  <td className="hidden py-2 text-right sm:table-cell">
                    <div className="flex justify-end">
                      <Sparkline
                        values={r.last30}
                        color={isSelected ? ACCENT : MUTED_LINE}
                        width={80}
                        height={22}
                        label={`${r.name} son 30 gün günlük DEX hacmi`}
                      />
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {report.missing.length ? (
        <p className="mt-3 text-[11px] leading-relaxed text-muted">
          Veri yok: {report.missing.map((m) => `${m.name} (${m.reason})`).join(' · ')}
        </p>
      ) : null}
    </Panel>
  );
}
