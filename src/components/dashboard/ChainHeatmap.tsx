import { Crown, Flame } from 'lucide-react';
import { CHAIN_LIST, CHAINS, type ChainId } from '@/lib/chains';
import { formatNumber, formatUsd } from '@/lib/format';
import { heatColor, heatInk } from '@/lib/theme';
import { ACTIVITY_METRICS, type ActivityMetric, type ChainActivity } from '@/lib/types';
import { ChainBadge } from '../ui/ChainBadge';
import { HeatLegend } from '../ui/HeatLegend';
import { Meter } from '../ui/Meter';
import { Panel } from '../ui/Panel';
import { Sparkline } from '../ui/Sparkline';

const METRICS: Record<ActivityMetric, { label: string; format: (v: number | null) => string }> = {
  volume24hUsd: { label: 'Hacim 24s', format: formatUsd },
  volume1hUsd: { label: 'Hacim 1s', format: formatUsd },
  txCount1h: { label: 'TX 1s', format: formatNumber },
  newPools1h: { label: 'Yeni havuz 1s', format: formatNumber },
  tvlUsd: { label: 'TVL', format: formatUsd },
};

const pct = (x: number) => `%${Math.round(x * 100)}`;

function FlowBar({ chains }: { chains: ChainActivity[] }) {
  const total = chains.reduce((a, c) => a + (c.metrics.volume1hUsd ?? 0), 0);
  return (
    <div>
      <div className="mb-1.5 flex items-baseline justify-between text-xs">
        <span className="font-medium text-ink-2">Sıcak para nerede? · 1s hacim payı</span>
        <span className="text-muted">toplam {formatUsd(total)}</span>
      </div>
      <div className="flex h-3 w-full gap-[2px] overflow-hidden rounded-[4px]" role="img" aria-label={chains.map((c) => `${CHAINS[c.chain].name} ${pct(c.volumeShare)}`).join(', ')}>
        {chains.map((c) => (
          <div
            key={c.chain}
            className="h-full first:rounded-l-[4px] last:rounded-r-[4px]"
            style={{ width: `${c.volumeShare * 100}%`, minWidth: c.volumeShare > 0 ? 3 : 0, backgroundColor: CHAINS[c.chain].color }}
            title={`${CHAINS[c.chain].name}: ${pct(c.volumeShare)} · ${formatUsd(c.metrics.volume1hUsd)}`}
          />
        ))}
      </div>
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs">
        {chains.map((c) => (
          <li key={c.chain} className="flex items-center gap-1.5">
            <span className="h-2.5 w-3 rounded-[2px]" style={{ backgroundColor: CHAINS[c.chain].color }} aria-hidden />
            <span className="text-ink-2">{CHAINS[c.chain].name}</span>
            <span className="font-semibold text-ink">{pct(c.volumeShare)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function HeatCell({ metric, value, heat }: { metric: ActivityMetric; value: number | null; heat: number | null }) {
  const { label, format } = METRICS[metric];
  const percentile = heat === null ? null : Math.round(heat * 100);
  const description = `${label}: ${format(value)}${percentile === null ? '' : ` — 7 günlük geçmişin ${percentile}. persentili`}`;
  return (
    <div
      className="min-w-0 rounded-[4px] px-1.5 py-1.5"
      style={{ backgroundColor: heatColor(heat), color: heatInk(heat) }}
      title={description}
      aria-label={description}
      role="img"
    >
      <div className="truncate text-[10px] leading-tight opacity-85">{label}</div>
      <div className="truncate text-xs leading-tight font-semibold">{format(value)}</div>
      <div className="text-[10px] leading-tight opacity-85">{percentile === null ? '—' : `p${percentile}`}</div>
    </div>
  );
}

function ChainRow({ activity, leader }: { activity: ChainActivity; leader: boolean }) {
  const meta = CHAINS[activity.chain];
  const color = heatColor(activity.activityIndex / 100);
  return (
    <div className="rounded-lg border border-line bg-raised/40 p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <ChainBadge chain={activity.chain} className="text-sm" />
          {leader ? (
            <span className="inline-flex items-center gap-1 rounded border border-accent/40 px-1.5 py-0.5 text-[10px] font-semibold tracking-wide text-accent uppercase">
              <Crown className="size-3" aria-hidden />
              Lider
            </span>
          ) : null}
        </div>
        <Sparkline
          values={activity.indexHistory}
          color={meta.color}
          label={`${meta.name} son 24 saat Activity Index: ${activity.indexHistory.join(', ')}`}
        />
      </div>

      <div className="mt-1 flex flex-wrap items-end gap-x-2 gap-y-1">
        <span className="text-3xl leading-none font-semibold text-ink">{activity.activityIndex}</span>
        <span className="pb-0.5 text-xs text-muted">/100</span>
        <span
          className="mb-0.5 rounded px-1.5 py-0.5 text-[11px] font-semibold"
          style={{ backgroundColor: color, color: heatInk(activity.activityIndex / 100) }}
        >
          {activity.label}
        </span>
        <span className="ml-auto pb-0.5 text-[11px] text-muted">
          momentum <span className="text-ink-2">{pct(activity.momentum)}</span> · baskınlık{' '}
          <span className="text-ink-2">{pct(activity.dominance)}</span>
        </span>
      </div>
      <Meter value={activity.activityIndex} color={color} label={`${meta.name} Activity Index`} className="mt-2" />

      <div className="mt-3 grid grid-cols-[repeat(auto-fit,minmax(5.25rem,1fr))] gap-[2px]">
        {ACTIVITY_METRICS.map((m) => (
          <HeatCell key={m} metric={m} value={activity.metrics[m]} heat={activity.heat[m]} />
        ))}
      </div>
    </div>
  );
}

function EmptyRow({ chain }: { chain: ChainId }) {
  return (
    <div className="rounded-lg border border-line p-3 text-xs text-muted">
      <ChainBadge chain={chain} className="text-sm" />
      <p className="mt-1">Bu zincir için henüz veri yok (sağlayıcı kimliklerini ve worker log’larını kontrol edin).</p>
    </div>
  );
}

export function ChainHeatmap({ chains }: { chains: ChainActivity[] }) {
  const byId = new Map(chains.map((c) => [c.chain, c]));
  const leader = chains.reduce<ChainActivity | null>((best, c) => (!best || c.activityIndex > best.activityIndex ? c : best), null);
  return (
    <Panel
      title="Zincir Sıcaklık Haritası"
      icon={Flame}
      subtitle="Activity Index = %65 momentum (metriklerin kendi 7 günlük geçmişine göre persentili) + %35 hacim baskınlığı"
    >
      {chains.length > 0 ? <FlowBar chains={chains} /> : null}
      <div className="mt-4 space-y-3">
        {CHAIN_LIST.map((meta) => {
          const activity = byId.get(meta.id);
          return activity ? (
            <ChainRow key={meta.id} activity={activity} leader={activity.chain === leader?.chain} />
          ) : (
            <EmptyRow key={meta.id} chain={meta.id} />
          );
        })}
      </div>
      <div className="mt-3">
        <HeatLegend low="Kendi geçmişine göre sakin" high="zirvede" />
      </div>
    </Panel>
  );
}
