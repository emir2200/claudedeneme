import { HEAT_EMPTY, HEAT_RAMP } from '@/lib/theme';

export function HeatLegend({ low = 'Soğuk', high = 'Sıcak', showEmpty = false }: { low?: string; high?: string; showEmpty?: boolean }) {
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-muted">
      <div className="flex items-center gap-1.5">
        <span>{low}</span>
        <span className="flex gap-0.5" aria-hidden>
          {HEAT_RAMP.map((c) => (
            <span key={c} className="h-2.5 w-4 rounded-[2px]" style={{ backgroundColor: c }} />
          ))}
        </span>
        <span>{high}</span>
      </div>
      {showEmpty ? (
        <div className="flex items-center gap-1.5">
          <span className="h-2.5 w-4 rounded-[2px]" style={{ backgroundColor: HEAT_EMPTY }} aria-hidden />
          <span>Veri yok</span>
        </div>
      ) : null}
    </div>
  );
}
