import type { LucideIcon } from 'lucide-react';
import { useId, type ReactNode } from 'react';

interface PanelProps {
  title: string;
  subtitle?: ReactNode;
  icon: LucideIcon;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}

export function Panel({ title, subtitle, icon: Icon, actions, children, className = '' }: PanelProps) {
  const id = useId();
  return (
    <section
      aria-labelledby={id}
      className={`min-w-0 rounded-xl border border-line bg-panel/95 p-4 shadow-[0_0_24px_-12px_rgb(56_189_248/0.25)] ${className}`}
    >
      <header className="mb-3 flex flex-wrap items-start justify-between gap-x-3 gap-y-2">
        <div className="flex min-w-0 items-start gap-2">
          <Icon className="mt-0.5 size-4 shrink-0 text-accent" aria-hidden />
          <div className="min-w-0">
            <h2 id={id} className="text-[13px] font-semibold tracking-[0.08em] text-ink uppercase">
              {title}
            </h2>
            {subtitle ? <p className="mt-0.5 text-xs leading-snug text-muted">{subtitle}</p> : null}
          </div>
        </div>
        {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
      </header>
      {children}
    </section>
  );
}
