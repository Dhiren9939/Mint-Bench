// colours from the css variables, and the chart.js defaults every chart shares. Imported once, after styles.css.
import Chart from 'chart.js/auto';

const css = (n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim();

export const C = {
  ink: css('--ink'), muted: css('--muted'), grid: css('--grid'), card: css('--card'), brand: css('--brand'),
  a: css('--a'), b: css('--b'), c: css('--c'), d: css('--d'), e: css('--e'), f: css('--f'), g: css('--g'),
  good: css('--good'), bad: css('--bad'), s1: css('--shade1'), s2: css('--shade2'), s3: css('--shade3'),
};
export const RC = [C.a, C.b, C.c, C.d, C.e];          // one colour per version, always in this order
export const PICK = [C.a, C.b, C.c, C.d, C.e, C.f, C.g]; // colours for attempts ticked in the compare section

Chart.defaults.color = C.muted;
Chart.defaults.borderColor = C.grid;
Chart.defaults.font.family = '"Instrument Sans", system-ui, -apple-system, "Segoe UI", sans-serif';
Chart.defaults.font.size = 12;
Chart.defaults.maintainAspectRatio = false;
Chart.defaults.animation = false;
Chart.defaults.interaction = { mode: 'nearest', axis: 'x', intersect: false };
Chart.defaults.scale.grid.color = C.grid;
Chart.defaults.scale.border = { display: false };
// round the tick labels, a zoomed in edge tick would otherwise read 2,714.6
Chart.defaults.scales.linear.ticks.callback = (v) => Number(Number(v).toPrecision(3)).toLocaleString();

const lg = Chart.defaults.plugins.legend.labels;
lg.usePointStyle = true; lg.boxWidth = 8; lg.boxHeight = 8;
const baseLabels = lg.generateLabels;
lg.generateLabels = (chart) => baseLabels(chart).map((l) => {
  const d = chart.data.datasets[l.datasetIndex];
  l.pointStyle = 'circle';
  l.strokeStyle = d.borderColor;
  l.fillStyle = d.borderDash ? 'transparent' : d.borderColor;
  return l;
});

const tt = Chart.defaults.plugins.tooltip;
Object.assign(tt, { backgroundColor: C.ink, titleColor: C.card, bodyColor: C.card, cornerRadius: 8, padding: 10, boxPadding: 4, usePointStyle: true });
tt.callbacks.label = (c) => `${c.dataset.label}: ${Number(c.parsed.y).toLocaleString(undefined, { maximumFractionDigits: 1 })}`;

// a dashed vertical line at the hovered point
Chart.register({
  id: 'crosshair',
  afterDatasetsDraw(chart) {
    const a = chart.tooltip && chart.tooltip.getActiveElements ? chart.tooltip.getActiveElements() : [];
    if (!a.length) return;
    const { ctx, chartArea: ca } = chart;
    ctx.save(); ctx.strokeStyle = C.muted; ctx.globalAlpha = .5; ctx.setLineDash([3, 3]); ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(a[0].element.x, ca.top); ctx.lineTo(a[0].element.x, ca.bottom); ctx.stroke(); ctx.restore();
  },
});
