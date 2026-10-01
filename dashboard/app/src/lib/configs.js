// the chart.js config for the one chart. Always returns a fresh config, a chart must never share one.
import { C } from '../theme.js';
import { RUNS, MIN_VUS, MAX_VUS, attemptOf, key } from './data.js';

const userTitle = (items) => `${Number(items[0].parsed.x).toLocaleString()} users`;
const dashed = (label, data) => ({ label, data, borderColor: C.e, borderDash: [5, 4], borderWidth: 1, pointRadius: 0, pointHoverRadius: 0 });
const line = (label, data, color) => ({ label, data, borderColor: color, backgroundColor: color, borderWidth: 2, tension: 0 });

// a dashed vertical line at the most users each version passed
const kneePlugin = {
  id: 'knees',
  afterDatasetsDraw(chart) {
    const { ctx, chartArea: ca, scales: { x } } = chart;
    ctx.save(); ctx.setLineDash([6, 4]); ctx.lineWidth = 1; ctx.globalAlpha = .7;
    RUNS.forEach((r) => {
      if (!r.best) return;
      const px = x.getPixelForValue(r.best.vus);
      if (px < ca.left || px > ca.right) return;
      ctx.strokeStyle = r.color; ctx.beginPath(); ctx.moveTo(px, ca.top); ctx.lineTo(px, ca.bottom); ctx.stroke();
    });
    ctx.restore();
  },
};

// shades the warm up, bench and warm down parts of a time chart
const phasePlugin = {
  id: 'phases',
  beforeDatasetsDraw(chart, _a, o) {
    if (!o || !o.warm) return;
    const { ctx, chartArea: ca, scales: { x } } = chart;
    const edges = [[x.min, o.warm, C.s1, 'warm up'], [o.warm, o.warm + o.bench, C.s2, 'bench'], [o.warm + o.bench, x.max, C.s3, 'warm down']];
    ctx.save();
    ctx.font = '11px "Instrument Sans", system-ui'; ctx.textBaseline = 'top';
    for (const [from, to, col, name] of edges) {
      const l = Math.max(ca.left, x.getPixelForValue(from)), r = Math.min(ca.right, x.getPixelForValue(to));
      if (r <= l) continue;
      ctx.fillStyle = col; ctx.fillRect(l, ca.top, r - l, ca.bottom - ca.top);
      ctx.fillStyle = C.muted; ctx.fillText(name, l + 6, ca.top + 4);
    }
    ctx.restore();
  },
};

// round steps on the time axis, whole minutes when zoomed out and seconds when zoomed in
const timeTicks = (scale) => {
  const span = scale.max - scale.min;
  const step = [1, 2, 5, 10, 15, 30, 60, 120, 300].find((s) => span / s <= 11) || 300;
  const ticks = [];
  for (let v = Math.ceil(scale.min / step) * step; v <= scale.max + 1e-9; v += step) ticks.push({ value: v });
  scale.ticks = ticks;
};
const minutes = (v) => {
  const s = Math.round(Math.abs(v)), sign = v < 0 ? '-' : '';
  return s % 60 === 0 ? `${sign}${s / 60}m` : `${sign}${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};

const yScale = (m) => ({ beginAtZero: true, suggestedMax: m.max, title: { display: true, text: m.unit } });

// x is 'users' (a line per version, a point per attempt) or 'time' (a line per picked attempt, minutes since the start)
export function chartConfig(m, x, picked) {
  if (x === 'users') {
    const on = new Set(picked.map((p) => p.k));
    const extra = [];
    if (m.limit) extra.push(dashed(`limit ${m.limit} ms`, [{ x: MIN_VUS, y: m.limit }, { x: MAX_VUS, y: m.limit }]));
    if (m.expected) extra.push(dashed(`expected at ${m.expected} per user`, [{ x: MIN_VUS, y: MIN_VUS * m.expected }, { x: MAX_VUS, y: MAX_VUS * m.expected }]));
    return {
      type: 'line', plugins: [kneePlugin],
      data: { datasets: [...RUNS.map((r) => ({
        ...line(r.label, r.byUsers.map((a) => ({ x: a.vus, y: m.scalar ? m.scalar(a) : null })), r.color),
        pointStyle: r.byUsers.map((a) => a.result === 'pass' ? 'circle' : 'rectRot'),
        pointBackgroundColor: r.byUsers.map((a) => a.result === 'pass' ? r.color : C.card),
        pointBorderColor: r.color,
        pointBorderWidth: r.byUsers.map((a) => on.has(key(a)) ? 4 : 2),
        pointRadius: r.byUsers.map((a) => on.has(key(a)) ? 9 : 6), pointHoverRadius: 10,
      })), ...extra] },
      options: {
        parsing: false, spanGaps: true,
        scales: { y: yScale(m), x: { type: 'linear', title: { display: true, text: 'users' } } },
        plugins: { legend: { position: 'bottom' }, tooltip: { callbacks: { title: userTitle } } },
      },
    };
  }
  const list = picked.map((p) => ({ a: attemptOf(p.k), color: p.color }));
  const first = list.length ? list[0].a : RUNS[0].attempts[0];
  const end = first.warmup_s + first.bench_s + first.cooldown_s;
  const sets = m.series ? list.map(({ a, color }) => line(`${a.run.label}, ${a.vus} users`, m.series(a), color)) : [];
  if (sets.length && m.limit) sets.push(dashed(`limit ${m.limit} ms`, [{ x: -60, y: m.limit }, { x: end, y: m.limit }]));
  return {
    type: 'line', plugins: [phasePlugin],
    data: { datasets: sets },
    options: {
      parsing: false, spanGaps: true,
      scales: { x: { type: 'linear', min: -60, afterBuildTicks: timeTicks, ticks: { callback: minutes }, title: { display: true, text: 'minutes since the start' } }, y: yScale(m) },
      plugins: { legend: { position: 'bottom' }, tooltip: { callbacks: { title: (i) => `${(i[0].parsed.x / 60).toFixed(1)} min` } }, phases: { warm: first.warmup_s, bench: first.bench_s } },
      elements: { point: { radius: 0, hoverRadius: 4 }, line: { borderWidth: 2, tension: 0 } },
    },
  };
}
