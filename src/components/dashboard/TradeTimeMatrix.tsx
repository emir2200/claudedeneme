'use client';

import { Activity, Clock, Flame, Moon, Timer, Trophy } from 'lucide-react';
import { useEffect, useMemo, useState, type KeyboardEvent } from 'react';
import { rotateCells } from '@/lib/analytics/tradeWindows';
import { CHAIN_LIST } from '@/lib/chains';
import { DAY_NAMES, DAY_NAMES_LONG, formatNumber, formatRatio, formatUsd, formatUtcOffset, hourLabel } from '@/lib/format';
import { heatColor } from '@/lib/theme';
import type { MatrixKey, TradeLevel, TradeWindowReport } from '@/lib/types';
import { HeatLegend } from '../ui/HeatLegend';
import { Panel } from '../ui/Panel';
import { SegmentedControl } from '../ui/SegmentedControl';
import { TableToggle } from '../ui/TableToggle';

const LEVELS: Record<TradeLevel, { text: string; icon: typeof Flame; className: string }> = {
  aktif: { text: 'AKTİF SAAT', icon: Flame, className: 'border-warn/50 bg-warn/10 text-warn' },
  normal: { text: 'NORMAL', icon: Activity, className: 'border-accent/40 bg-accent/10 text-accent' },
  sakin: { text: 'SAKİN', icon: Moon, className: 'border-line bg-raised text-ink-2' },
};

const pctText = (x: number | null) => (x === null ? '—' : `%${Math.round(x * 100)}`);

/** Tarayıcının UTC farkı (saat). Sunucu render'ında 0; istemcide mount sonrası ayarlanır. */
function useLocalOffset(): number {
  const [offset, setOffset] = useState(0);
  useEffect(() => setOffset(Math.round(-new Date().getTimezoneOffset() / 60)), []);
  return offset;
}

export function TradeTimeMatrix({ report, generatedAt }: { report: TradeWindowReport; generatedAt: string }) {
  const [key, setKey] = useState<MatrixKey>('all');
  const [useLocal, setUseLocal] = useState(true);
  const [showTable, setShowTable] = useState(false);
  const [active, setActive] = useState<number | null>(null);
  const localOffset = useLocalOffset();
  const offset = useLocal ? localOffset : 0;

  const cells = useMemo(() => rotateCells(report.matrices[key], offset), [report.matrices, key, offset]);
  const now = new Date(generatedAt);
  const nowIndex = (((now.getUTCDay() + 6) % 7) * 24 + now.getUTCHours() + offset + 168) % 168;
  const best = report.best[key];
  const bestStart = (best.dow * 24 + best.startHour + offset + 168) % 168;
  const inBest = (i: number) => (i - bestStart + 168) % 168 < best.length;
  const status = report.now[key];
  const recent = report.recent[key];
  const level = LEVELS[status.level];
  const LevelIcon = level.icon;
  const tzLabel = formatUtcOffset(offset);

  const describe = (i: number) => {
    const c = cells[i]!;
    const d = Math.floor(i / 24);
    const h = i % 24;
    if (c.samples === 0) return `${DAY_NAMES_LONG[d]} ${hourLabel(h)}: veri yok`;
    return `${DAY_NAMES_LONG[d]} ${hourLabel(h)}–${hourLabel(h + 1)} (${tzLabel}) · sıcaklık ${Math.round(c.heat * 100)}/100 · medyan hacim ${formatUsd(c.volumeUsd)} · ${formatNumber(c.txCount)} tx · insan payı ${pctText(c.humanShare)} · volatilite %${c.volatilityPct.toFixed(1)}`;
  };

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const moves: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: 24, ArrowUp: -24 };
    const delta = moves[e.key];
    if (delta === undefined) return;
    e.preventDefault();
    setActive((a) => ((a ?? nowIndex) + delta + 168) % 168);
  };

  const recentHour = recent ? new Date(recent.hourStart).getUTCHours() + offset : null;

  return (
    <Panel
      title="En Aktif Trade Zamanı"
      icon={Clock}
      subtitle={`Son ${report.weeks} haftanın saatlik medyan hacmi (%55), volatilite (%25) ve insan işlem payından (%20) — 24 saat × 7 gün`}
      actions={<TableToggle showTable={showTable} onToggle={() => setShowTable((s) => !s)} />}
    >
      <div className="flex flex-wrap items-center gap-2">
        <SegmentedControl
          label="Ağ"
          value={key}
          onChange={setKey}
          options={[{ value: 'all', label: 'Tümü' }, ...CHAIN_LIST.map((c) => ({ value: c.id, label: c.shortName }))]}
        />
        <SegmentedControl
          label="Saat dilimi"
          value={useLocal ? 'local' : 'utc'}
          onChange={(v) => setUseLocal(v === 'local')}
          options={[
            { value: 'local', label: `Yerel (${formatUtcOffset(localOffset)})` },
            { value: 'utc', label: 'UTC' },
          ]}
        />
      </div>

      <div className="mt-3 grid gap-2 sm:grid-cols-3">
        <div className="rounded-lg border border-line bg-raised/40 p-2.5">
          <div className="text-[11px] text-muted">Şu an</div>
          <div className={`mt-1 inline-flex items-center gap-1.5 rounded border px-1.5 py-0.5 text-xs font-semibold ${level.className}`}>
            <LevelIcon className="size-3.5" aria-hidden />
            {level.text}
          </div>
          <div className="mt-1 text-[11px] text-muted">
            {status.liveRatio === null ? 'canlı hacim yok' : `canlı hacim normalin ${formatRatio(status.liveRatio, 1)}`}
          </div>
        </div>
        <div className="rounded-lg border border-line bg-raised/40 p-2.5">
          <div className="flex items-center gap-1 text-[11px] text-muted">
            <Timer className="size-3" aria-hidden /> Son 4 saatin en sıcağı
          </div>
          <div className="mt-1 text-sm font-semibold text-ink">
            {recentHour === null ? '—' : `${hourLabel(recentHour)}–${hourLabel(recentHour + 1)}`}
          </div>
          <div className="text-[11px] text-muted">{recent ? `${formatUsd(recent.volumeUsd)} · ${formatNumber(recent.txCount)} tx` : ''}</div>
        </div>
        <div className="rounded-lg border border-line bg-raised/40 p-2.5">
          <div className="flex items-center gap-1 text-[11px] text-muted">
            <Trophy className="size-3" aria-hidden /> Haftanın en iyi penceresi
          </div>
          <div className="mt-1 text-sm font-semibold text-ink">
            {DAY_NAMES_LONG[Math.floor(bestStart / 24)]} {hourLabel(bestStart % 24)}–{hourLabel((bestStart % 24) + best.length)}
          </div>
          <div className="text-[11px] text-muted">ort. sıcaklık {Math.round(best.avgHeat * 100)}/100</div>
        </div>
      </div>

      {showTable ? (
        <div className="mt-3 max-h-72 overflow-auto rounded-md border border-line">
          <table className="tabular w-full text-[11px]">
            <caption className="sr-only">Gün × saat sıcaklık tablosu ({tzLabel}), 0–100</caption>
            <thead className="sticky top-0 bg-raised text-muted">
              <tr>
                <th className="px-1.5 py-1 text-left font-medium">Gün</th>
                {Array.from({ length: 24 }, (_, h) => (
                  <th key={h} className="px-1 py-1 text-right font-medium">
                    {String(h).padStart(2, '0')}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {DAY_NAMES.map((d, di) => (
                <tr key={d} className="border-t border-line">
                  <th className="px-1.5 py-1 text-left font-medium text-ink-2">{d}</th>
                  {Array.from({ length: 24 }, (_, h) => {
                    const c = cells[di * 24 + h]!;
                    return (
                      <td key={h} className="px-1 py-1 text-right text-ink">
                        {c.samples ? Math.round(c.heat * 100) : '—'}
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="relative mt-3 overflow-x-auto pb-1">
          <div
            role="grid"
            tabIndex={0}
            aria-label={`Gün × saat trade sıcaklık matrisi (${tzLabel}). Ok tuşlarıyla gezinin.`}
            aria-activedescendant={active === null ? undefined : `cell-${active}`}
            onKeyDown={onKeyDown}
            onFocus={() => setActive((a) => a ?? nowIndex)}
            onBlur={() => setActive(null)}
            onMouseLeave={() => setActive(null)}
            className="grid min-w-[300px] gap-[2px] rounded-md"
            style={{ gridTemplateColumns: '1.75rem repeat(24, minmax(0, 1fr))' }}
          >
            {DAY_NAMES.map((d, di) => (
              <div key={d} role="row" className="contents">
                <div role="rowheader" className="flex items-center text-[11px] text-muted">
                  {d}
                </div>
                {Array.from({ length: 24 }, (_, h) => {
                  const i = di * 24 + h;
                  const c = cells[i]!;
                  const isNow = i === nowIndex;
                  return (
                    <div
                      key={i}
                      id={`cell-${i}`}
                      role="gridcell"
                      aria-label={describe(i)}
                      aria-selected={active === i}
                      onMouseEnter={() => setActive(i)}
                      className="relative h-5 rounded-[3px] sm:h-6"
                      style={{
                        backgroundColor: heatColor(c.samples ? c.heat : null),
                        boxShadow: [
                          isNow ? 'inset 0 0 0 2px #38bdf8' : '',
                          active === i ? '0 0 0 2px #f2f4f8' : '',
                        ]
                          .filter(Boolean)
                          .join(', ') || undefined,
                      }}
                    >
                      {inBest(i) ? (
                        <span className="absolute inset-x-0.5 -bottom-[3px] h-[2px] rounded bg-accent" aria-hidden />
                      ) : null}
                    </div>
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
      )}

      <div className="mt-2 min-h-[2.5rem] rounded-md bg-raised/40 px-2.5 py-1.5 text-[11px] text-ink-2" aria-live="polite">
        {active === null ? (
          <span className="text-muted">Bir hücrenin üzerine gelin veya ızgaraya odaklanıp ok tuşlarıyla gezinin.</span>
        ) : (
          describe(active)
        )}
      </div>

      <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
        <HeatLegend low="Sakin" high="En yoğun" showEmpty />
        <div className="flex flex-wrap items-center gap-3 text-[11px] text-muted">
          <span className="flex items-center gap-1.5">
            <span className="size-3 rounded-[3px] shadow-[inset_0_0_0_2px_#38bdf8]" aria-hidden /> şu an
          </span>
          <span className="flex items-center gap-1.5">
            <span className="h-[2px] w-3 rounded bg-accent" aria-hidden /> en iyi 3 saat
          </span>
          <span>{tzLabel}</span>
        </div>
      </div>
    </Panel>
  );
}
