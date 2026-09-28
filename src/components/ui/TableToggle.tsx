'use client';

import { ChartColumn, Table2 } from 'lucide-react';

/** Grafik ↔ tablo görünümü (her grafiğin erişilebilir tablo eşleniği vardır). */
export function TableToggle({ showTable, onToggle }: { showTable: boolean; onToggle: () => void }) {
  const Icon = showTable ? ChartColumn : Table2;
  return (
    <button
      type="button"
      onClick={onToggle}
      aria-pressed={showTable}
      className="inline-flex items-center gap-1 rounded-md border border-line px-2 py-1 text-xs text-muted transition-colors hover:bg-raised hover:text-ink-2"
    >
      <Icon className="size-3.5" aria-hidden />
      {showTable ? 'Grafik' : 'Tablo'}
    </button>
  );
}
