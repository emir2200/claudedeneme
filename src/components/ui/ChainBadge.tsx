import { CHAINS, type ChainId } from '@/lib/chains';

/** Zincir kimliği: renkli nokta + adı. Metin her zaman mürekkep renginde kalır. */
export function ChainBadge({ chain, short = false, className = '' }: { chain: ChainId; short?: boolean; className?: string }) {
  const meta = CHAINS[chain];
  return (
    <span className={`inline-flex items-center gap-1.5 text-xs font-medium text-ink-2 ${className}`}>
      <span className="size-2.5 shrink-0 rounded-full" style={{ backgroundColor: meta.color }} aria-hidden />
      {short ? meta.shortName : meta.name}
    </span>
  );
}

/** Sıkışık satırlar için: nokta + kısaltma (kimlik yalnızca renkle verilmez). */
export function ChainTag({ chain }: { chain: ChainId }) {
  return (
    <span className="inline-flex shrink-0 items-center gap-1 text-[10px] font-medium text-muted">
      <span className="size-2 rounded-full" style={{ backgroundColor: CHAINS[chain].color }} aria-hidden />
      {CHAINS[chain].shortName}
    </span>
  );
}

export function ChainDot({ chain }: { chain: ChainId }) {
  return (
    <span
      className="inline-block size-2 shrink-0 rounded-full"
      style={{ backgroundColor: CHAINS[chain].color }}
      title={CHAINS[chain].name}
      aria-label={CHAINS[chain].name}
    />
  );
}
