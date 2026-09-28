interface SparklineProps {
  values: readonly number[];
  color: string;
  width?: number;
  height?: number;
  label: string;
  /** Alan dolgusu (%10 opaklık) */
  area?: boolean;
}

/** Küçük eğilim çizgisi: 2px çizgi, yüzey halkalı uç noktası. */
export function Sparkline({ values, color, width = 96, height = 28, label, area = true }: SparklineProps) {
  if (values.length < 2) return null;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const pad = 4;
  const x = (i: number) => pad + (i / (values.length - 1)) * (width - pad * 2);
  const y = (v: number) => (max === min ? height / 2 : pad + (1 - (v - min) / (max - min)) * (height - pad * 2));
  const points = values.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
  const lastX = x(values.length - 1);
  const lastY = y(values[values.length - 1]!);

  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} role="img" aria-label={label} className="shrink-0 overflow-visible">
      <title>{label}</title>
      {area ? (
        <polygon
          points={`${x(0)},${height - pad} ${points} ${lastX},${height - pad}`}
          fill={color}
          fillOpacity={0.1}
        />
      ) : null}
      <polyline points={points} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={lastX} cy={lastY} r={3.5} fill={color} stroke="var(--color-panel)" strokeWidth={2} />
    </svg>
  );
}
