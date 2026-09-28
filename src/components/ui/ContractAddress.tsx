'use client';

import { Check, Copy, ExternalLink, Info, ShieldAlert } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { tokenLinks, type ChainId } from '@/lib/chains';

type CopyState = 'idle' | 'copied' | 'selected';

/**
 * Tam kontrat adresi (CA). Popüler memecoin'lerin aynı sembolle çok sayıda sahte kopyası
 * çıktığı için adres kısaltılmadan, seçilebilir ve kopyalanabilir biçimde gösterilir.
 * Demo modunda adres uydurmadır: kopyalama ve doğrulama bağlantıları gizlenir, açıkça
 * "örnek" olarak işaretlenir.
 */
export function ContractAddress({
  chain,
  address,
  symbol,
  demo,
}: {
  chain: ChainId;
  address: string;
  symbol: string;
  demo: boolean;
}) {
  const [state, setState] = useState<CopyState>('idle');
  const codeRef = useRef<HTMLElement>(null);

  useEffect(() => {
    if (state === 'idle') return;
    const id = setTimeout(() => setState('idle'), 2500);
    return () => clearTimeout(id);
  }, [state]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(address);
      setState('copied');
    } catch {
      // Pano erişimi reddedildiyse adresi seçili bırak; kullanıcı kendisi kopyalar.
      const node = codeRef.current;
      const selection = window.getSelection();
      if (node && selection) selection.selectAllChildren(node);
      setState('selected');
    }
  };

  if (demo) {
    return (
      <div className="mt-3 rounded-md border border-line bg-page/60 p-2.5">
        <span className="text-[11px] font-semibold tracking-wide text-muted uppercase">CA · demo örneği</span>
        <code className="mt-1.5 block font-mono text-[12px] leading-snug break-all text-muted">{address}</code>
        <p className="mt-1.5 flex items-start gap-1.5 text-[11px] leading-snug text-ink-2">
          <Info className="mt-px size-3.5 shrink-0 text-accent" aria-hidden />
          <span>
            Bu adres simülasyonun uydurduğu bir örnektir, gerçek bir token’a ait değildir. Kopyalama ve doğrulama
            bağlantıları canlı modda, gerçek adreslerle açılır.
          </span>
        </p>
      </div>
    );
  }

  const label = state === 'copied' ? 'Kopyalandı' : state === 'selected' ? 'Seçildi, Ctrl+C' : 'Kopyala';
  const Icon = state === 'copied' ? Check : Copy;

  return (
    <div className="mt-3 rounded-md border border-line bg-page/60 p-2.5">
      <div className="flex items-center justify-between gap-2">
        <span className="text-[11px] font-semibold tracking-wide text-muted uppercase">CA · kontrat adresi</span>
        <button
          type="button"
          onClick={copy}
          aria-label={`$${symbol} kontrat adresini kopyala`}
          className="inline-flex shrink-0 items-center gap-1 rounded-md border border-accent/40 px-2 py-0.5 text-[11px] font-medium text-accent transition-colors hover:bg-accent/10"
        >
          <Icon className="size-3.5" aria-hidden />
          <span aria-live="polite">{label}</span>
        </button>
      </div>
      <code ref={codeRef} className="mt-1.5 block font-mono text-[12px] leading-snug break-all text-ink select-all">
        {address}
      </code>
      {tokenLinks(chain, address).length ? (
        <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px]">
          {tokenLinks(chain, address).map((l) => (
            <a
              key={l.label}
              href={l.href}
              target="_blank"
              rel="noreferrer noopener"
              className="inline-flex items-center gap-1 text-accent hover:underline"
            >
              {l.label}
              <ExternalLink className="size-3" aria-hidden />
            </a>
          ))}
        </div>
      ) : null}
      <p className="mt-1.5 flex items-start gap-1.5 text-[11px] leading-snug text-warn">
        <ShieldAlert className="mt-px size-3.5 shrink-0" aria-hidden />
        <span>
          ${symbol} sembolüyle sahte kopyalar çıkıyor. İşlem yapmadan önce kullandığın adresin bununla birebir aynı
          olduğunu kontrol et.
        </span>
      </p>
    </div>
  );
}
