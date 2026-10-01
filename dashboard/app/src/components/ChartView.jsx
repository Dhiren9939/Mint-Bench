import { useMemo, useRef, useState } from 'react';
import { useChart } from '../lib/useChart.js';
import { zoomBy, resetView } from '../lib/interactions.js';
import { chartConfig } from '../lib/configs.js';
import { available } from '../lib/metrics.js';

// the one chart. Drag draws a zoom band (sideways zooms x, up and down zooms y), shift and drag moves, scroll zooms,
// double click resets. Drag on an axis to change only that axis.
export default function ChartView({ metric, x, picked }) {
  const moveRef = useRef(false);
  const [move, setMove] = useState(false);
  const build = useMemo(() => () => chartConfig(metric, x, picked), [metric, x, picked]);
  const { canvasRef, chartRef } = useChart(build, { ctrl: false, getMove: () => moveRef.current, name: 'main' });
  const mode = (m) => { moveRef.current = m; setMove(m); };
  const zoom = (f) => chartRef.current && zoomBy(chartRef.current, f, 'xy');

  const msg = !available(metric, x) ? 'This one only exists ' + (x === 'users' ? 'over time.' : 'by users.')
    : x === 'time' && picked.length === 0 ? 'Pick attempts on the right to draw them over time.' : null;

  return (
    <div className="chartbox">
      <div className="chart-head">
        <h2>{metric.group === 'Latency' ? `${metric.name} latency` : `${metric.group} ${metric.name}`}<small>{metric.unit}</small></h2>
        <div className="seg" role="group" aria-label="What dragging does">
          <button type="button" className={move ? '' : 'on'} onClick={() => mode(false)}>Zoom</button>
          <button type="button" className={move ? 'on' : ''} onClick={() => mode(true)}>Move</button>
        </div>
        <button type="button" className="btn" onClick={() => zoom(1.3)} aria-label="Zoom in">+</button>
        <button type="button" className="btn" onClick={() => zoom(1 / 1.3)} aria-label="Zoom out">&minus;</button>
        <button type="button" className="btn" onClick={() => chartRef.current && resetView(chartRef.current)}>Reset</button>
      </div>
      <div className="chart">
        <canvas ref={canvasRef} />
        {msg && <div className="msg">{msg}</div>}
      </div>
      <p className="hint">Drag to zoom, shift and drag to move, scroll to zoom, double click to reset. Drag along an axis to change only that axis.</p>
    </div>
  );
}
