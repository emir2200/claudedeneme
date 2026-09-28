import { Flame } from 'lucide-react';
import { CHAINS } from '@/lib/chains';
import { formatPct, formatUsd } from '@/lib/format';
import type { NarrativeTrend, TickerItem } from '@/lib/types';
import { ChainDot } from '../ui/ChainBadge';
import { Delta } from '../ui/Delta';

function Items({ items, narrative }: { items: TickerItem[]; narrative: NarrativeTrend | null }) {
  return (
    <>
      {narrative ? (
        <li className="flex items-center gap-2 pr-8">
          <Flame className="size-3.5 text-warn" aria-hidden />
          <span className="text-muted">Yükselen narrative</span>
          <span className="font-semibold text-ink">{narrative.name}</span>
          <span className="text-up">{formatPct(narrative.mentionGrowthPct, 0)} mention</span>
        </li>
      ) : null}
      {items.map((t) => (
        <li key={`${t.chain}:${t.symbol}`} className="flex items-center gap-2 pr-8">
          <ChainDot chain={t.chain} />
          <span className="font-semibold text-ink">${t.symbol}</span>
          <Delta value={t.priceChange24hPct} digits={0} />
          <span className="text-muted">
            {CHAINS[t.chain].shortName} · hacim {formatUsd(t.volume24hUsd)}
          </span>
        </li>
      ))}
    </>
  );
}

/** Üst bant: günün en çok yükselenleri ve trend narrative. Fareyle üzerine gelince durur. */
export function TickerBanner({ items, narrative }: { items: TickerItem[]; narrative: NarrativeTrend | null }) {
  if (items.length === 0 && !narrative) return null;
  return (
    <div className="relative overflow-hidden rounded-lg border border-line bg-panel/80 py-2 font-mono text-xs">
      <span className="absolute inset-y-0 left-0 z-10 flex items-center gap-1.5 bg-panel px-3 font-sans text-[11px] font-semibold tracking-wider text-accent uppercase shadow-[8px_0_12px_var(--color-panel)]">
        Top 24s
      </span>
      <div className="ticker-track flex w-max" aria-label="Günün en çok yükselen memecoin'leri">
        <ul className="flex">
          <Items items={items} narrative={narrative} />
        </ul>
        <ul className="flex" aria-hidden>
          <Items items={items} narrative={narrative} />
        </ul>
      </div>
    </div>
  );
}
