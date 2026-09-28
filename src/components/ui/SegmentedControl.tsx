'use client';

interface Option<T extends string> {
  value: T;
  label: React.ReactNode;
}

interface SegmentedControlProps<T extends string> {
  label: string;
  value: T;
  options: readonly Option<T>[];
  onChange: (value: T) => void;
}

export function SegmentedControl<T extends string>({ label, value, options, onChange }: SegmentedControlProps<T>) {
  return (
    <div role="radiogroup" aria-label={label} className="inline-flex rounded-md border border-line bg-page/60 p-0.5">
      {options.map((o) => {
        const selected = o.value === value;
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={selected}
            onClick={() => onChange(o.value)}
            className={`inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium transition-colors ${
              selected ? 'bg-raised text-ink shadow-[inset_0_0_0_1px_rgb(56_189_248/0.45)]' : 'text-muted hover:bg-raised/60 hover:text-ink-2'
            }`}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
