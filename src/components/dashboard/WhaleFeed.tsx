'use client';

import { ArrowDownRight, ArrowUpRight, ExternalLink, Fish, Sparkles } from 'lucide-react';
import { useState } from 'react';
import { CHAIN_IDS, CHAINS } from '@/lib/chains';
import { formatUsd, shortAddress, timeAgo } from '@/lib/format';
import type { WhaleReport } from '@/lib/types';
import { ChainBadge, ChainTag } from '../ui/ChainBadge';
import { Panel } from '../ui/Panel';

export function WhaleFeed({ report, generatedAt }: { report: WhaleReport; generatedAt: string }) {
  const [smartOnly, setSmartOnly] = useState(false);
  const now = Date.parse(generatedAt);
  const trades = smartOnly ? report.trades.filter((t) => t.isSmartMoney) : report.trades;

  return (
    <Panel
      title="Smart Money & Balinalar"
      icon={Fish}
      subtitle={`${formatUsd(report.minUsd)} ve üzeri swaplar · net akış son 1 saat`}
      actions={
        <label className="inline-flex cursor-pointer items-center gap-1.5 text-xs text-muted">
          <input
            type="checkbox"
            checked={smartOnly}
            onChange={(e) => setSmartOnly(e.target.checked)}
            className="size-3.5 accent-sky-400"
          />
          Yalnız smart money
        </label>
      }
    >
      <div className="grid grid-cols-3 gap-1.5">
        {CHAIN_IDS.map((c) => {
          const f = report.netFlow1h[c];
          const net = f.buyUsd - f.sellUsd;
          const Icon = net >= 0 ? ArrowUpRight : ArrowDownRight;
          return (
            <div key={c} className="min-w-0 rounded-md bg-raised/50 px-2 py-1.5">
              <ChainBadge chain={c} short />
              <div className={`mt-0.5 flex items-center gap-0.5 text-xs font-semibold whitespace-nowrap ${f.count === 0 ? 'text-muted' : net >= 0 ? 'text-up' : 'text-down'}`}>
                {f.count === 0 ? '—' : (
                  <>
                    <Icon className="size-3.5 shrink-0" aria-hidden />
                    {net >= 0 ? '+' : '−'}
                    {formatUsd(Math.abs(net))}
                  </>
                )}
              </div>
              <div className="text-[11px] text-muted">{f.count} işlem</div>
            </div>
          );
        })}
      </div>

      <ul className="mt-3 max-h-[26rem] space-y-1 overflow-y-auto pr-1">
        {trades.length === 0 ? <li className="py-4 text-center text-xs text-muted">Kayıt yok</li> : null}
        {trades.map((t) => {
          const buy = t.side === 'BUY';
          const explorer = CHAINS[t.chain].explorerTxUrl;
          return (
            <li key={t.id} className="rounded-md border border-line/60 bg-raised/30 px-2 py-1.5">
              <div className="flex items-center justify-between gap-2 text-xs">
                <span className="flex min-w-0 items-center gap-1.5">
                  <span
                    className={`inline-flex shrink-0 items-center gap-0.5 rounded px-1 py-0.5 text-[10px] font-bold ${
                      buy ? 'bg-up/15 text-up' : 'bg-down/15 text-down'
                    }`}
                  >
                    {buy ? <ArrowUpRight className="size-3" aria-hidden /> : <ArrowDownRight className="size-3" aria-hidden />}
                    {buy ? 'ALIM' : 'SATIM'}
                  </span>
                  <ChainTag chain={t.chain} />
                  <span className="truncate font-mono font-semibold text-ink">${t.tokenSymbol ?? shortAddress(t.tokenAddress)}</span>
                </span>
                <span className="shrink-0 font-semibold text-ink tabular">{formatUsd(t.usdValue)}</span>
              </div>
              <div className="mt-0.5 flex items-center justify-between gap-2 text-[11px] text-muted">
                <span className="flex min-w-0 items-center gap-1.5">
                  <span className="font-mono">{shortAddress(t.wallet)}</span>
                  {t.isSmartMoney ? (
                    <span className="inline-flex min-w-0 items-center gap-0.5 text-accent">
                      <Sparkles className="size-3 shrink-0" aria-hidden />
                      <span className="truncate">{t.walletLabel ?? 'Smart Money'}</span>
                    </span>
                  ) : null}
                </span>
                <span className="flex shrink-0 items-center gap-1.5">
                  {timeAgo(t.blockTime, now)}
                  {explorer ? (
                    <a
                      href={`${explorer}${t.txHash}`}
                      target="_blank"
                      rel="noreferrer noopener"
                      className="text-muted hover:text-accent"
                      aria-label="İşlemi blok gezgininde aç"
                    >
                      <ExternalLink className="size-3" aria-hidden />
                    </a>
                  ) : null}
                </span>
              </div>
            </li>
          );
        })}
      </ul>
    </Panel>
  );
}
