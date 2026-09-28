/** 0–100 ölçer: dolu kısım değeri, iz aynı tonun soluk adımıdır. */
export function Meter({ value, color, label, className = '' }: { value: number; color: string; label: string; className?: string }) {
  const pct = Math.max(0, Math.min(100, value));
  return (
    <div
      role="meter"
      aria-label={label}
      aria-valuenow={Math.round(pct)}
      aria-valuemin={0}
      aria-valuemax={100}
      className={`h-1.5 w-full overflow-hidden rounded-full ${className}`}
      style={{ backgroundColor: `color-mix(in oklab, ${color} 18%, transparent)` }}
    >
      <div className="h-full rounded-full" style={{ width: `${pct}%`, backgroundColor: color }} />
    </div>
  );
}
