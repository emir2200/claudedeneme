import { ArrowDownRight, ArrowUpRight } from 'lucide-react';
import { formatPct } from '@/lib/format';

/** İşaretli değişim: yön hem ok ikonu hem renk hem de işaretle gösterilir. */
export function Delta({ value, digits = 1, className = '' }: { value: number | null; digits?: number; className?: string }) {
  if (value === null || !Number.isFinite(value)) return <span className={`text-muted ${className}`}>—</span>;
  const up = value >= 0;
  const Icon = up ? ArrowUpRight : ArrowDownRight;
  return (
    <span className={`inline-flex items-center gap-0.5 font-medium ${up ? 'text-up' : 'text-down'} ${className}`}>
      <Icon className="size-3.5 shrink-0" aria-hidden />
      {formatPct(value, digits)}
    </span>
  );
}
