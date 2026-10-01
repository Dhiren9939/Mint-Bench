import { useEffect, useRef } from 'react';
import Chart from 'chart.js/auto';
import { attachInteractions, rememberView } from './interactions.js';

// Makes a chart.js chart on a canvas from build() (it returns a fresh chart config) and tears it down again.
// The chart is only rebuilt when build changes, so keep build memoized, otherwise the zoom would reset.
// name puts the chart on window.__charts, which is handy in the console.
export function useChart(build, { ctrl, getMove, name }) {
  const canvasRef = useRef(null);
  const chartRef = useRef(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    const cfg = build();
    const chart = new Chart(canvas, cfg);
    rememberView(chart, cfg);
    chartRef.current = chart;
    if (name) (window.__charts ||= {})[name] = chart;
    const off = attachInteractions(canvas.parentElement, () => chartRef.current, getMove, ctrl);
    return () => {
      off();
      chart.destroy();
      chartRef.current = null;
      if (name && window.__charts && window.__charts[name] === chart) delete window.__charts[name];
    };
  }, [build]);   // eslint-disable-line react-hooks/exhaustive-deps
  return { canvasRef, chartRef };
}
