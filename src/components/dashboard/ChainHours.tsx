'use client';

import { Activity, Clock, Flame, Moon, RotateCw, Sunrise, TriangleAlert } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import {
  Bar,
  CartesianGrid,
  Cell,
  ComposedChart,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  type TooltipContentProps,
} from 'recharts';
import { rotate } from '@/lib/analytics/hours';
import { DAY_NAMES, DAY_NAMES_LONG, formatRatio, formatUsd, formatUtcOffset, hourLabel } from '@/lib/format';
import { heatColor } from '@/lib/theme';
import type { ActivityLevel, ChainRanking, HoursReport } from '@/lib/types';
import { HeatLegend } from '../ui/HeatLegend';
import { Panel } from '../ui/Panel';
import { SegmentedControl } from '../ui/SegmentedControl';
import { TableToggle } from '../ui/TableToggle';

const ACCENT = '#38bdf8';
const DEEMPHASIS = '#56657f';
const TODAY = '#f1b206';
const AXIS = { fill: '#7d8494', fontSize: 11 };

const LEVELS: Record<ActivityLevel, { text: string; icon: typeof Flame; className: string }> = {
  aktif: { text: 'AKTİF SAAT', icon: Flame, className: 'border-warn/50 bg-warn/10 text-warn' },
  normal: { text: 'NORMAL', icon: Activity, className: 'border-accent/40 bg-accent/10 text-accent' },
  sakin: { text: 'SAKİN', icon: Moon, className: 'border-line bg-raised text-ink-2' },
};

/** Tarayıcının UTC farkı (saat). Sunucu render'ında 0; istemcide mount sonrası ayarlanır. */
function useLocalOffset(): number {
  const [offset, setOffset] = useState(0);
  useEffect(() => setOffset(Math.round(-new Date().getTimezoneOffset() / 60)), []);
  return offset;
}

const range = (start: number, length: number) => `${hourLabel(start)}–${hourLabel(start + length)}`;
const pct1 = (share: number) => (share * 100).toLocaleString('tr-TR', { minimumFractionDigits: 1, maximumFractionDigits: 1 });

interface ChartRow {
  hour: number;
  typical: number;
  share: number;
  today: number | null;
  best: boolean;
}

function ChartTooltip({ active, payload, tzLabel }: TooltipContentProps<number, string> & { tzLabel: string }) {
  const row = payload?.[0]?.payload as ChartRow | undefined;
  if (!active || !row) return null;
  return (
    <div className="rounded-md border border-line bg-page/95 px-3 py-2 text-xs shadow-lg">
      <div className="mb-1 text-muted">
        {range(row.hour, 1)} ({tzLabel})
      </div>
      <div className="flex items-center gap-2">
        <span className="h-2.5 w-2.5 rounded-[2px]" style={{ backgroundColor: row.best ? ACCENT : DEEMPHASIS }} aria-hidden />
        <span className="font-semibold text-ink tabular">{formatUsd(row.typical)}</span>
        <span className="text-muted">tipik · günlük hacmin %{pct1(row.share)}’i</span>
      </div>
      {row.today !== null ? (
        <div className="flex items-center gap-2">
          <span className="h-0.5 w-2.5 rounded" style={{ backgroundColor: TODAY }} aria-hidden />
          <span className="font-semibold text-ink tabular">{formatUsd(row.today)}</span>
          <span className="text-muted">bugün</span>
        </div>
      ) : null}
    </div>
  );
}

function WeekMatrix({ report, offset, tzLabel, nowIndex }: { report: HoursReport; offset: number; tzLabel: string; nowIndex: number }) {
  const cells = useMemo(() => rotate(report.matrix, offset), [report.matrix, offset]);
  const [active, setActive] = useState<number | null>(null);
  const describe = (i: number) => {
    const c = cells[i]!;
    const d = Math.floor(i / 24);
    const h = i % 24;
    return c.samples
      ? `${DAY_NAMES_LONG[d]} ${range(h, 1)} (${tzLabel}) · medyan hacim ${formatUsd(c.volumeUsd)} · ${c.samples} haftanın medyanı`
      : `${DAY_NAMES_LONG[d]} ${range(h, 1)}: veri yok`;
  };
  return (
    <div>
      <div className="overflow-x-auto pb-1">
        <div
          className="grid min-w-[300px] gap-[2px]"
          style={{ gridTemplateColumns: '1.75rem repeat(24, minmax(0, 1fr))' }}
          onMouseLeave={() => setActive(null)}
          role="img"
          aria-label={`Haftanın her saati için son 4 haftanın medyan DEX hacmi (${tzLabel}). Değerler tablo görünümündedir.`}
        >
          {DAY_NAMES.map((d, di) => (
            <div key={d} className="contents">
              <div className="flex items-center text-[11px] text-muted">{d}</div>
              {Array.from({ length: 24 }, (_, h) => {
                const i = di * 24 + h;
                const c = cells[i]!;
                return (
                  <div
                    key={i}
                    title={describe(i)}
                    onMouseEnter={() => setActive(i)}
                    className="h-5 rounded-[3px] sm:h-6"
                    style={{
                      backgroundColor: heatColor(c.samples ? c.heat : null),
                      boxShadow: [i === nowIndex ? 'inset 0 0 0 2px #38bdf8' : '', active === i ? '0 0 0 2px #f2f4f8' : '']
                        .filter(Boolean)
                        .join(', ') || undefined,
                    }}
                  />
                );
              })}
            </div>
          ))}
          <div aria-hidden />
          {Array.from({ length: 24 }, (_, h) => (
            <div key={h} className="pt-1 text-center text-[10px] text-muted" aria-hidden>
              {h % 3 === 0 ? String(h).padStart(2, '0') : ''}
            </div>
          ))}
        </div>
      </div>
      <div className="mt-2 min-h-[2rem] rounded-md bg-raised/40 px-2.5 py-1.5 text-[11px] text-ink-2" aria-live="polite">
        {active === null ? <span className="text-muted">Bir hücrenin üzerine gelin.</span> : describe(active)}
      </div>
      <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
        <HeatLegend low="Sakin" high="En yoğun" showEmpty />
        <span className="flex items-center gap-1.5 text-[11px] text-muted">
          <span className="size-3 rounded-[3px] shadow-[inset_0_0_0_2px_#38bdf8]" aria-hidden /> şu an · {tzLabel}
        </span>
      </div>
    </div>
  );
}

export function ChainHours({
  rows,
  selected,
  onSelect,
  report,
  error,
  loading,
  onRetry,
}: {
  rows: ChainRanking[];
  selected: string | null;
  onSelect: (chain: string) => void;
  report: HoursReport | null;
  error: string | null;
  loading: boolean;
  onRetry: () => void;
}) {
  const [useLocal, setUseLocal] = useState(true);
  const [showTable, setShowTable] = useState(false);
  const localOffset = useLocalOffset();
  const offset = useLocal ? localOffset : 0;
  const tzLabel = formatUtcOffset(offset);
  const selectedName = rows.find((r) => r.chain === selected)?.name ?? selected ?? '';
  const outdated = report !== null && report.chain !== selected;

  const view = useMemo(() => {
    if (!report) return null;
    const profile = rotate(report.profile, offset);
    const today = rotate(report.today, offset);
    const best = (report.bestWindow.startHour + offset + 24) % 24;
    const quiet = (report.quietWindow.startHour + offset + 24) % 24;
    const inBest = (h: number) => (h - best + 24) % 24 < report.bestWindow.length;
    const chart: ChartRow[] = profile.map((p, h) => ({
      hour: h,
      typical: p.medianVolumeUsd,
      share: p.share,
      today: today[h] ?? null,
      best: inBest(h),
    }));
    const now = new Date(report.generatedAt);
    const nowHour = (now.getUTCHours() + offset + 24) % 24;
    const nowIndex = ((((now.getUTCDay() + 6) % 7) * 24 + now.getUTCHours() + offset) % 168 + 168) % 168;
    return { chart, best, quiet, nowHour, nowIndex };
  }, [report, offset]);

  const level = report?.lastHour ? LEVELS[report.lastHour.level] : null;
  const LevelIcon = level?.icon ?? Activity;
  const lastHourLocal = report?.lastHour ? (new Date(report.lastHour.hourStart).getUTCHours() + offset + 24) % 24 : null;

  return (
    <Panel
      title="Gün içi en aktif trade saatleri"
      icon={Clock}
      subtitle="Seçili chain'deki en yüksek hacimli havuzların son 28 günlük saatlik hacmi (GeckoTerminal)"
      actions={report ? <TableToggle showTable={showTable} onToggle={() => setShowTable((s) => !s)} /> : null}
    >
      <div className="flex flex-wrap items-center gap-2">
        <label className="flex items-center gap-2 text-xs text-muted" htmlFor="chain-select">
          Chain
          <select
            id="chain-select"
            value={selected ?? ''}
            onChange={(e) => onSelect(e.target.value)}
            className="rounded-md border border-line bg-page px-2 py-1 text-xs text-ink"
          >
            {rows.map((r) => (
              <option key={r.chain} value={r.chain}>
                {r.name}
              </option>
            ))}
          </select>
        </label>
        <SegmentedControl
          label="Saat dilimi"
          value={useLocal ? 'local' : 'utc'}
          onChange={(v) => setUseLocal(v === 'local')}
          options={[
            { value: 'local', label: `Yerel (${formatUtcOffset(localOffset)})` },
            { value: 'utc', label: 'UTC' },
          ]}
        />
        {loading ? <span className="text-[11px] text-muted">{selectedName} verisi yükleniyor…</span> : null}
        {report?.stale ? (
          <span className="inline-flex items-center gap-1 text-[11px] text-warn">
            <TriangleAlert className="size-3.5" aria-hidden /> kaynak yanıt vermiyor, son veri
          </span>
        ) : null}
      </div>

      {error && (!report || outdated) && !loading ? (
        <div className="mt-4 rounded-lg border border-down/40 bg-down/5 p-4 text-sm">
          <div className="flex items-start gap-2 text-down">
            <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
            <div>
              <div className="font-semibold">{selectedName} için saat verisi alınamadı</div>
              <div className="mt-0.5 text-xs text-ink-2">{error}</div>
            </div>
          </div>
          <button
            type="button"
            onClick={onRetry}
            className="mt-3 inline-flex items-center gap-1.5 rounded-md border border-line px-2.5 py-1 text-xs text-ink-2 hover:bg-raised"
          >
            <RotateCw className="size-3.5" aria-hidden /> Tekrar dene
          </button>
        </div>
      ) : null}

      {!report && !error ? (
        <p className="mt-4 text-sm text-muted">
          Saatlik veri yükleniyor… İlk yükleme GeckoTerminal'in istek sınırı yüzünden 10–20 saniye sürebilir.
        </p>
      ) : null}

      {report && view ? (
        <div className={outdated ? 'opacity-50 transition-opacity' : 'transition-opacity'} aria-busy={outdated}>
          {outdated ? <p className="mt-3 text-[11px] text-muted">Aşağıda hâlâ {report.name} gösteriliyor.</p> : null}
          <h3 className="mt-4 text-base font-semibold text-ink">{report.name}</h3>
          <div className="mt-2 grid gap-2 sm:grid-cols-3">
            <div className="rounded-lg border border-accent/30 bg-accent/5 p-2.5">
              <div className="flex items-center gap-1 text-[11px] text-muted">
                <Flame className="size-3 text-accent" aria-hidden /> En aktif saatler
              </div>
              <div className="mt-1 text-lg leading-tight font-semibold text-ink">{range(view.best, report.bestWindow.length)}</div>
              <div className="text-[11px] text-muted">
                günlük hacmin %{Math.round(report.bestWindow.share * 100)}’i · {tzLabel}
              </div>
            </div>
            <div className="rounded-lg border border-line bg-raised/40 p-2.5">
              <div className="flex items-center gap-1 text-[11px] text-muted">
                <Sunrise className="size-3" aria-hidden /> En sakin saatler
              </div>
              <div className="mt-1 text-lg leading-tight font-semibold text-ink">{range(view.quiet, report.quietWindow.length)}</div>
              <div className="text-[11px] text-muted">
                günlük hacmin %{Math.round(report.quietWindow.share * 100)}’i · {tzLabel}
              </div>
            </div>
            <div className="rounded-lg border border-line bg-raised/40 p-2.5">
              <div className="text-[11px] text-muted">Şu an</div>
              {report.lastHour && level ? (
                <>
                  <div className={`mt-1 inline-flex items-center gap-1.5 rounded border px-1.5 py-0.5 text-xs font-semibold ${level.className}`}>
                    <LevelIcon className="size-3.5" aria-hidden />
                    {level.text}
                  </div>
                  <div className="mt-1 text-[11px] text-muted">
                    son saat ({range(lastHourLocal!, 1)}):{' '}
                    {report.lastHour.ratio === null ? formatUsd(report.lastHour.volumeUsd) : `tipiğinin ${formatRatio(report.lastHour.ratio, 1)}’i`}
                  </div>
                </>
              ) : (
                <div className="mt-1 text-xs text-muted">veri yok</div>
              )}
            </div>
          </div>

          {showTable ? (
            <div className="mt-3 max-h-80 overflow-auto rounded-md border border-line">
              <table className="tabular w-full text-xs">
                <caption className="sr-only">{report.name} saatlik hacim tablosu ({tzLabel})</caption>
                <thead className="sticky top-0 bg-raised text-muted">
                  <tr>
                    <th className="px-2 py-1.5 text-left font-medium">Saat ({tzLabel})</th>
                    <th className="px-2 py-1.5 text-right font-medium">Tipik hacim</th>
                    <th className="px-2 py-1.5 text-right font-medium">Günlük pay</th>
                    <th className="px-2 py-1.5 text-right font-medium">Bugün</th>
                  </tr>
                </thead>
                <tbody>
                  {view.chart.map((r) => (
                    <tr key={r.hour} className={`border-t border-line ${r.best ? 'bg-accent/10' : ''}`}>
                      <td className="px-2 py-1 text-ink-2">{range(r.hour, 1)}</td>
                      <td className="px-2 py-1 text-right text-ink">{formatUsd(r.typical)}</td>
                      <td className="px-2 py-1 text-right text-ink">%{pct1(r.share)}</td>
                      <td className="px-2 py-1 text-right text-ink">{r.today === null ? '—' : formatUsd(r.today)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <>
              <ul className="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-ink-2" aria-label="Lejant">
                <li className="flex items-center gap-1.5">
                  <span className="h-2.5 w-2.5 rounded-[2px]" style={{ backgroundColor: ACCENT }} aria-hidden /> En aktif 3 saat
                </li>
                <li className="flex items-center gap-1.5">
                  <span className="h-2.5 w-2.5 rounded-[2px]" style={{ backgroundColor: DEEMPHASIS }} aria-hidden /> Tipik saat (28 günün medyanı)
                </li>
                <li className="flex items-center gap-1.5">
                  <span className="h-0.5 w-3 rounded" style={{ backgroundColor: TODAY }} aria-hidden /> Bugün (UTC günü)
                </li>
              </ul>
              <div className="mt-2 h-60 w-full">
                <ResponsiveContainer width="100%" height="100%" initialDimension={{ width: 600, height: 240 }}>
                  <ComposedChart data={view.chart} margin={{ top: 8, right: 4, bottom: 0, left: 4 }} barCategoryGap="12%">
                    <CartesianGrid vertical={false} stroke="#232733" />
                    <XAxis
                      dataKey="hour"
                      tickFormatter={(h: number) => String(h).padStart(2, '0')}
                      tick={AXIS}
                      tickLine={false}
                      axisLine={{ stroke: '#383835' }}
                      interval={2}
                    />
                    <YAxis tick={AXIS} tickLine={false} axisLine={false} tickFormatter={(v: number) => formatUsd(v)} width={80} />
                    <Tooltip
                      cursor={{ fill: 'rgb(255 255 255 / 0.04)' }}
                      content={(props) => <ChartTooltip {...(props as TooltipContentProps<number, string>)} tzLabel={tzLabel} />}
                    />
                    <ReferenceLine
                      x={view.nowHour}
                      stroke="#7d8494"
                      strokeWidth={1}
                      label={{ value: 'şimdi', position: 'insideTopRight', fill: '#aeb4c2', fontSize: 10 }}
                    />
                    <Bar dataKey="typical" radius={[4, 4, 0, 0]} maxBarSize={24} isAnimationActive={false}>
                      {view.chart.map((r) => (
                        <Cell key={r.hour} fill={r.best ? ACCENT : DEEMPHASIS} />
                      ))}
                    </Bar>
                    <Line
                      dataKey="today"
                      stroke={TODAY}
                      strokeWidth={2}
                      dot={false}
                      activeDot={{ r: 4, stroke: 'var(--color-panel)', strokeWidth: 2 }}
                      connectNulls={false}
                      isAnimationActive={false}
                    />
                  </ComposedChart>
                </ResponsiveContainer>
              </div>

              <h4 className="mt-5 mb-2 text-[11px] font-semibold tracking-wide text-muted uppercase">
                Haftanın saatleri · son 4 hafta
              </h4>
              <WeekMatrix report={report} offset={offset} tzLabel={tzLabel} nowIndex={view.nowIndex} />
            </>
          )}

          <p className="mt-3 text-[11px] leading-relaxed text-muted">
            Kaynak: GeckoTerminal · {report.pools.length} havuz ({report.pools.slice(0, 4).map((p) => p.name).join(', ')}
            {report.pools.length > 4 ? ', …' : ''}) · son {report.daysCovered} gün. Saatler, chain'in tamamını değil en
            büyük havuzlarını temsil eder.
          </p>
        </div>
      ) : null}
    </Panel>
  );
}
