'use client';

import { Rocket } from 'lucide-react';
import { useMemo, useState } from 'react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  type TooltipContentProps,
} from 'recharts';
import { LAUNCHPAD_NAMES } from '@/lib/analytics/launchpads';
import { CHAIN_IDS, CHAIN_LIST, CHAINS, type ChainId } from '@/lib/chains';
import { formatNumber, formatUsd, shortDate } from '@/lib/format';
import type { LaunchReport } from '@/lib/types';
import { ChainBadge } from '../ui/ChainBadge';
import { Delta } from '../ui/Delta';
import { Panel } from '../ui/Panel';
import { SegmentedControl } from '../ui/SegmentedControl';
import { TableToggle } from '../ui/TableToggle';

type View = 'daily' | 'trend';

const AXIS = { fill: '#7d8494', fontSize: 11 };
const GRID = '#232733';

/** Son 30 günden, bugün hariç tam günler üzerinde 7 günlük hareketli ortalama. */
function movingAverage(days: LaunchReport['days']) {
  const complete = days.slice(0, -1);
  return complete.slice(6).map((d, i) => {
    const window = complete.slice(i, i + 7);
    const avg = (c: ChainId) => window.reduce((a, w) => a + w[c], 0) / window.length;
    return { date: d.date, solana: avg('solana'), bsc: avg('bsc'), robinhood: avg('robinhood') };
  });
}

function ChartTooltip({ active, payload, label, todayKey, decimals }: TooltipContentProps<number, string> & { todayKey: string; decimals: number }) {
  if (!active || !payload?.length) return null;
  const day = String(label);
  return (
    <div className="rounded-md border border-line bg-page/95 px-3 py-2 text-xs shadow-lg">
      <div className="mb-1 text-muted">
        {shortDate(day)}
        {day === todayKey ? ' · gün sürüyor' : ''}
      </div>
      {payload.map((p) => {
        const chain = p.dataKey as ChainId;
        return (
          <div key={chain} className="flex items-center gap-2">
            <span className="h-0.5 w-3 rounded" style={{ backgroundColor: CHAINS[chain].color }} aria-hidden />
            <span className="font-semibold text-ink tabular">
              {Number(p.value).toLocaleString('tr-TR', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}
            </span>
            <span className="text-muted">{CHAINS[chain].name}</span>
          </div>
        );
      })}
    </div>
  );
}

function StatTile({ chain, report }: { chain: ChainId; report: LaunchReport }) {
  const t = report.today[chain];
  // Gün sonu temposu: şu ana kadarki sayı / günün geçen kısmı, 7 günlük ortalamaya göre.
  const projected = report.dayProgress > 0.05 ? t.count / report.dayProgress : null;
  const pace = projected !== null && t.avg7d > 0 ? (projected / t.avg7d - 1) * 100 : null;
  return (
    <div className="min-w-0 rounded-lg border border-line bg-raised/40 p-2.5">
      <ChainBadge chain={chain} short />
      <div className="mt-1 text-2xl leading-none font-semibold text-ink">{formatNumber(t.count)}</div>
      <div className="mt-1 text-[11px] leading-snug text-muted">
        dün {formatNumber(t.yesterday)} · 7g ort. {formatNumber(Math.round(t.avg7d))}
      </div>
      <div className="mt-1 flex flex-wrap items-center gap-x-1 text-[11px] text-muted">
        tempo <Delta value={pace} digits={0} className="text-[11px]" />
      </div>
      {t.topLaunchpad ? (
        <div className="mt-0.5 truncate text-[11px] text-muted">
          {LAUNCHPAD_NAMES[t.topLaunchpad.launchpad]} %{Math.round(t.topLaunchpad.share * 100)}
        </div>
      ) : null}
    </div>
  );
}

export function LaunchMeter({ report }: { report: LaunchReport }) {
  const [view, setView] = useState<View>('daily');
  const [showTable, setShowTable] = useState(false);
  const daily = report.days.slice(-14);
  const trend = useMemo(() => movingAverage(report.days), [report.days]);
  const todayKey = report.days[report.days.length - 1]?.date ?? '';

  return (
    <Panel
      title="100K+ Çıkış Sayacı"
      icon={Rocket}
      subtitle={`Günlük (UTC) ${formatUsd(report.thresholdUsd)} piyasa değeri veya likidite eşiğini ilk kez aşan token sayısı`}
      actions={<TableToggle showTable={showTable} onToggle={() => setShowTable((s) => !s)} />}
    >
      <div className="grid grid-cols-3 gap-2">
        {CHAIN_IDS.map((c) => (
          <StatTile key={c} chain={c} report={report} />
        ))}
      </div>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-2">
        <SegmentedControl
          label="Grafik görünümü"
          value={view}
          onChange={setView}
          options={[
            { value: 'daily', label: 'Günlük · 14g' },
            { value: 'trend', label: 'Eğilim · 7g ort.' },
          ]}
        />
        <ul className="flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-ink-2" aria-label="Lejant">
          {CHAIN_LIST.map((c) => (
            <li key={c.id} className="flex items-center gap-1.5">
              {view === 'daily' ? (
                <span className="h-2.5 w-2.5 rounded-[2px]" style={{ backgroundColor: c.color }} aria-hidden />
              ) : (
                <span className="h-0.5 w-3 rounded" style={{ backgroundColor: c.color }} aria-hidden />
              )}
              {c.name}
            </li>
          ))}
        </ul>
      </div>

      {showTable ? (
        <div className="mt-3 max-h-64 overflow-auto rounded-md border border-line">
          <table className="tabular w-full text-xs">
            <caption className="sr-only">Günlük 100K+ çıkış sayıları</caption>
            <thead className="sticky top-0 bg-raised text-muted">
              <tr>
                <th className="px-2 py-1.5 text-left font-medium">Gün</th>
                {CHAIN_LIST.map((c) => (
                  <th key={c.id} className="px-2 py-1.5 text-right font-medium">
                    {c.name}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {[...report.days].reverse().map((d) => (
                <tr key={d.date} className="border-t border-line">
                  <td className="px-2 py-1 text-ink-2">
                    {shortDate(d.date)}
                    {d.date === todayKey ? ' (bugün)' : ''}
                  </td>
                  {CHAIN_IDS.map((c) => (
                    <td key={c} className="px-2 py-1 text-right text-ink">
                      {d[c]}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="mt-2 h-56 w-full">
          <ResponsiveContainer width="100%" height="100%" initialDimension={{ width: 400, height: 224 }}>
            {view === 'daily' ? (
              <BarChart data={daily} margin={{ top: 8, right: 4, bottom: 0, left: -18 }} barGap={2} barCategoryGap="22%">
                <CartesianGrid vertical={false} stroke={GRID} />
                <XAxis dataKey="date" tickFormatter={shortDate} tick={AXIS} tickLine={false} axisLine={{ stroke: '#383835' }} interval="preserveStartEnd" minTickGap={16} />
                <YAxis tick={AXIS} tickLine={false} axisLine={false} allowDecimals={false} />
                <Tooltip
                  cursor={{ fill: 'rgb(255 255 255 / 0.04)' }}
                  content={(props) => <ChartTooltip {...(props as TooltipContentProps<number, string>)} todayKey={todayKey} decimals={0} />}
                />
                {CHAIN_IDS.map((c) => (
                  <Bar key={c} dataKey={c} name={CHAINS[c].name} fill={CHAINS[c].color} radius={[4, 4, 0, 0]} maxBarSize={14} isAnimationActive={false}>
                    {daily.map((d) => (
                      // Bugünün çubuğu henüz tamamlanmadı: soluk gösterilir.
                      <Cell key={d.date} fillOpacity={d.date === todayKey ? 0.45 : 1} />
                    ))}
                  </Bar>
                ))}
              </BarChart>
            ) : (
              <LineChart data={trend} margin={{ top: 8, right: 28, bottom: 0, left: -18 }}>
                <CartesianGrid vertical={false} stroke={GRID} />
                <XAxis dataKey="date" tickFormatter={shortDate} tick={AXIS} tickLine={false} axisLine={{ stroke: '#383835' }} interval="preserveStartEnd" minTickGap={24} />
                <YAxis tick={AXIS} tickLine={false} axisLine={false} allowDecimals={false} />
                <Tooltip
                  cursor={{ stroke: '#7d8494', strokeWidth: 1 }}
                  content={(props) => <ChartTooltip {...(props as TooltipContentProps<number, string>)} todayKey={todayKey} decimals={1} />}
                />
                {CHAIN_IDS.map((c) => (
                  <Line
                    key={c}
                    type="monotone"
                    dataKey={c}
                    name={CHAINS[c].name}
                    stroke={CHAINS[c].color}
                    strokeWidth={2}
                    dot={false}
                    activeDot={{ r: 4, stroke: 'var(--color-panel)', strokeWidth: 2 }}
                    isAnimationActive={false}
                    label={({ index, x, y, value }) =>
                      index === trend.length - 1 ? (
                        <text key={c} x={Number(x) + 6} y={Number(y) + 4} fontSize={11} fill="#aeb4c2">
                          {Math.round(Number(value))}
                        </text>
                      ) : null
                    }
                  />
                ))}
              </LineChart>
            )}
          </ResponsiveContainer>
        </div>
      )}
    </Panel>
  );
}
