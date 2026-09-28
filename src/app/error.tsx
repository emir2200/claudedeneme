'use client';

import { TriangleAlert } from 'lucide-react';

export default function ErrorPage({ reset }: { error: Error; reset: () => void }) {
  return (
    <div className="mx-auto mt-24 max-w-md rounded-xl border border-line bg-panel p-6 text-center">
      <TriangleAlert className="mx-auto size-8 text-warn" aria-hidden />
      <h1 className="mt-3 text-lg font-semibold text-ink">Veri şu anda yüklenemiyor</h1>
      <p className="mt-1 text-sm text-muted">
        Canlı modda veritabanı veya Redis bağlantısını kontrol edin; demo modu için <code>DATA_MODE=demo</code>.
      </p>
      <button
        type="button"
        onClick={reset}
        className="mt-4 rounded-md border border-accent/40 px-3 py-1.5 text-sm text-accent hover:bg-accent/10"
      >
        Tekrar dene
      </button>
    </div>
  );
}
