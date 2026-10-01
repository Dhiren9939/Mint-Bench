// Zoom and move for a chart.js chart, without a plugin so every change goes through one clamp.
//
// Dragging on the chart: the direction decides which axis changes, sideways is x, up and down is y, diagonal is both.
// Dragging on an axis (the numbers) changes only that axis. In zoom mode the drag draws a band and zooms into it,
// in move mode it pans (hold shift to move in zoom mode). Scrolling, or a two finger pinch on a trackpad (it arrives as ctrl and scroll), zooms around
// the cursor, over an axis only that axis zooms. Zooming out stops at the full view, zooming in at 1/MAX_ZOOM of it.

export const MAX_ZOOM = 50;

// the view of an axis is never wider than the full range, never narrower than 1/MAX_ZOOM of it, and stays inside it
export function setRange(chart, a, min, max) {
  const [f0, f1] = chart.$full[a], span = f1 - f0, narrowest = span / MAX_ZOOM;
  const w = Math.min(span, Math.max(narrowest, max - min));
  const mid = (min + max) / 2;
  min = mid - w / 2; max = mid + w / 2;
  if (min < f0) { max += f0 - min; min = f0; }
  if (max > f1) { min -= max - f1; max = f1; }
  const o = chart.scales[a].options;
  o.min = min; o.max = max;
  chart.update('none');
}

// zoom by a factor (above 1 zooms in) around a point in pixels, or around the middle of the axis
export function zoomBy(chart, f, axes, pt) {
  for (const a of axes) {
    const sc = chart.scales[a];
    const v = pt ? sc.getValueForPixel(a === 'x' ? pt[0] : pt[1]) : (sc.min + sc.max) / 2;
    setRange(chart, a, v - (v - sc.min) / f, v + (sc.max - v) / f);
  }
}

// back to the view the chart started with
export function resetView(chart) {
  for (const a of ['x', 'y']) {
    const o = chart.scales[a].options;
    o.min = chart.$orig[a].min; o.max = chart.$orig[a].max;
  }
  chart.update('none');
}

// remembers the full range and the starting min and max, call right after the chart is created
export function rememberView(chart, cfg) {
  const so = cfg.options.scales;
  chart.$orig = { x: { min: so.x.min, max: so.x.max }, y: { min: so.y.min, max: so.y.max } };
  chart.$full = { x: [chart.scales.x.min, chart.scales.x.max], y: [chart.scales.y.min, chart.scales.y.max] };
}

// wires the drag and scroll handling on a chart. getChart and getMove are functions so the same wiring
// follows the chart when it is rebuilt. ctrl: scrolling only zooms with ctrl held, so the page can still scroll.
// Returns a function that takes everything off again.
export function attachInteractions(wrap, getChart, getMove, ctrl) {
  const canvas = wrap.querySelector('canvas');
  const band = document.createElement('div');
  band.className = 'band'; band.hidden = true;
  wrap.appendChild(band);
  const offs = [];
  const on = (el, type, fn, opts) => { el.addEventListener(type, fn, opts); offs.push(() => el.removeEventListener(type, fn, opts)); };

  const zoneAt = (chart, x, y) => {
    const ca = chart.chartArea, sx = chart.scales.x, sy = chart.scales.y;
    if (x >= ca.left && x <= ca.right && y >= ca.top && y <= ca.bottom) return 'plot';
    if (x >= sx.left && x <= sx.right && y >= sx.top && y <= sx.bottom) return 'x';
    if (x >= sy.left && x <= sy.right && y >= sy.top && y <= sy.bottom) return 'y';
    return null;
  };
  const pos = (e) => { const r = canvas.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
  const lock = (dx, dy) => { const ax = Math.abs(dx), ay = Math.abs(dy); return ay < ax * 0.35 ? 'x' : ax < ay * 0.35 ? 'y' : 'xy'; };
  const swallow = (e) => {
    const chart = getChart(); if (!chart) return;
    const [x, y] = pos(e.touches ? e.touches[0] : e);
    if (zoneAt(chart, x, y)) { e.preventDefault(); e.stopImmediatePropagation(); }
  };
  on(wrap, 'mousedown', swallow, true);
  on(wrap, 'touchstart', swallow, { capture: true, passive: false });

  on(wrap, 'pointerdown', (e) => {
    if (e.button !== 0) return;
    const chart = getChart(); if (!chart) return;
    const [x0, y0] = pos(e);
    const zone = zoneAt(chart, x0, y0);
    if (!zone) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const moving = getMove() || e.shiftKey;   // shift while dragging always moves
    const start = { x: [chart.scales.x.min, chart.scales.x.max], y: [chart.scales.y.min, chart.scales.y.max] };
    let cur = [x0, y0];
    const axesOf = () => zone === 'plot' ? lock(cur[0] - x0, cur[1] - y0) : zone;
    const move = (ev) => {
      cur = pos(ev);
      const dx = cur[0] - x0, dy = cur[1] - y0, axes = axesOf(), ca = chart.chartArea;
      if (moving) {
        band.hidden = true;
        for (const a of ['x', 'y']) {
          const sc = chart.scales[a], span = start[a][1] - start[a][0];
          const d = !axes.includes(a) ? 0 : a === 'x' ? -dx / sc.width * span : dy / sc.height * span;
          setRange(chart, a, start[a][0] + d, start[a][1] + d);
        }
      } else {
        const clampX = (v) => Math.min(ca.right, Math.max(ca.left, v)), clampY = (v) => Math.min(ca.bottom, Math.max(ca.top, v));
        const l = axes.includes('x') ? clampX(Math.min(x0, cur[0])) : ca.left, r = axes.includes('x') ? clampX(Math.max(x0, cur[0])) : ca.right;
        const t = axes.includes('y') ? clampY(Math.min(y0, cur[1])) : ca.top, b = axes.includes('y') ? clampY(Math.max(y0, cur[1])) : ca.bottom;
        Object.assign(band.style, { left: l + 'px', top: t + 'px', width: (r - l) + 'px', height: (b - t) + 'px' });
        band.hidden = false;
      }
    };
    const up = () => {
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', up);
      document.removeEventListener('pointercancel', up);
      band.hidden = true;
      if (moving) return;
      const axes = axesOf();
      for (const a of ['x', 'y']) {
        const p0 = a === 'x' ? x0 : y0, p1 = a === 'x' ? cur[0] : cur[1];
        const sc = chart.scales[a];
        if (axes.includes(a) && Math.abs(p1 - p0) >= 6) {
          const v0 = sc.getValueForPixel(p0), v1 = sc.getValueForPixel(p1);
          setRange(chart, a, Math.min(v0, v1), Math.max(v0, v1));
        } else {
          setRange(chart, a, start[a][0], start[a][1]);   // the other axis stays where it was
        }
      }
    };
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', up);
    document.addEventListener('pointercancel', up);
    offs.push(() => { document.removeEventListener('pointermove', move); document.removeEventListener('pointerup', up); document.removeEventListener('pointercancel', up); });
  }, true);

  on(wrap, 'pointermove', (e) => {
    const chart = getChart(); if (!chart) return;
    const p = pos(e), z = zoneAt(chart, p[0], p[1]);
    canvas.style.cursor = z === 'x' ? 'ew-resize' : z === 'y' ? 'ns-resize' : getMove() ? 'grab' : 'crosshair';
  });
  on(wrap, 'wheel', (e) => {
    const chart = getChart(); if (!chart) return;
    const p = pos(e), z = zoneAt(chart, p[0], p[1]);
    if (!z || (ctrl && !e.ctrlKey)) return;
    e.preventDefault(); e.stopImmediatePropagation();
    zoomBy(chart, Math.exp(-e.deltaY * 0.002), z === 'plot' ? 'xy' : z, p);
  }, { capture: true, passive: false });
  on(canvas, 'dblclick', () => { const c = getChart(); if (c) resetView(c); });

  return () => { offs.forEach((off) => off()); band.remove(); };
}
