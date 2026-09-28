import { CalendarDays, CalendarRange, Sun } from 'lucide-react';
import { formatUsd, shortDate } from '@/lib/format';
import type { ChainRanking, Period } from '@/lib/types';
import { Delta } from '../ui/Delta';

const PERIOD_META: Record<Period, { title: string; window: (asOf: string | null) => string; vs: string; icon: typeof Sun }> = {
  day: { title: 'Günün en aktif chain’i', window: (d) => (d ? `${shortDate(d)} (UTC)` : 'son tam gün'), vs: 'önceki güne göre', icon: Sun },
  week: { title: 'Haftanın en aktif chain’i', window: () => 'son 7 gün', vs: 'önceki 7 güne göre', icon: CalendarRange },
  month: { title: 'Ayın en aktif chain’i', window: () => 'son 30 gün', vs: 'önceki 30 güne göre', icon: CalendarDays },
};

function Leader({ period, rows, asOfDay, onSelect }: { period: Period; rows: ChainRanking[]; asOfDay: string | null; onSelect: (chain: string) => void }) {
  const meta = PERIOD_META[period];
  const Icon = meta.icon;
  const sorted = [...rows].sort((a, b) => a.stats[period].rank - b.stats[period].rank);
  const leader = sorted[0];
  if (!leader) return null;
  const s = leader.stats[period];
  return (
    <button
      type="button"
      onClick={() => onSelect(leader.chain)}
      className="min-w-0 rounded-xl border border-line bg-panel/95 p-4 text-left transition-colors hover:border-accent/40"
      aria-label={`${meta.title}: ${leader.name}. Saatlerini göster`}
    >
      <div className="flex items-center gap-1.5 text-[11px] font-semibold tracking-[0.08em] text-muted uppercase">
        <Icon className="size-3.5 text-accent" aria-hidden />
        {meta.title}
      </div>
      <div className="mt-2 truncate text-2xl font-semibold text-ink">{leader.name}</div>
      <div className="mt-1 flex flex-wrap items-baseline gap-x-2 text-sm">
        <span className="font-semibold text-ink">{formatUsd(s.volumeUsd)}</span>
        <span className="text-xs text-muted">DEX hacmi · {meta.window(asOfDay)}</span>
      </div>
      <div className="mt-1 flex flex-wrap items-center gap-x-3 text-xs text-muted">
        <span>
          pay <span className="text-ink-2">%{Math.round(s.share * 100)}</span>
        </span>
        <span className="inline-flex items-center gap-1">
          <Delta value={s.changePct} className="text-xs" /> {s.changePct === null ? '' : meta.vs}
        </span>
      </div>
      {sorted.length > 1 ? (
        <div className="mt-2 truncate text-[11px] text-muted">
          {sorted
            .slice(1, 3)
            .map((r) => `${r.stats[period].rank}. ${r.name} ${formatUsd(r.stats[period].volumeUsd)}`)
            .join(' · ')}
        </div>
      ) : null}
    </button>
  );
}

export function PeriodLeaders({ rows, asOfDay, onSelect }: { rows: ChainRanking[]; asOfDay: string | null; onSelect: (chain: string) => void }) {
  return (
    <section aria-label="Dönem liderleri" className="grid gap-4 md:grid-cols-3">
      {(['day', 'week', 'month'] as const).map((p) => (
        <Leader key={p} period={p} rows={rows} asOfDay={asOfDay} onSelect={onSelect} />
      ))}
    </section>
  );
}
