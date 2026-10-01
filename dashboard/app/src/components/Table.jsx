import { useMemo, useState } from 'react';
import { everyAttempt, key, bench, benchAvg, K, machine, loadgen, num, f, ms } from '../lib/data.js';

const pct = (d = 0) => (v) => v == null ? '-' : f(v, d) + '%';
const col = (name, get, fmt = (v) => (v == null ? '-' : v)) => ({ name, get, fmt });

// every number of the bench part of an attempt. Click a header to sort.
const COLS = [
  col('version', (a) => a.run.i, (_, a) => a.run.label),
  col('users', (a) => a.vus, (v) => v.toLocaleString()),
  col('result', (a) => a.result, (v) => <span className="res"><span className={`mark ${v}`} />{v}</span>),
  col('req/s', (a) => num(bench(a).rps), (v) => f(v, 0)),
  col('p50', (a) => num(bench(a).p50_ms), ms),
  col('p95', (a) => num(bench(a).p95_ms), ms),
  col('p99', (a) => num(bench(a).p99_ms), ms),
  col('max', (a) => num(bench(a).max_ms), ms),
  col('failed', (a) => num(bench(a).failed_rate), (v) => v == null ? '-' : f(v * 100, 2) + '%'),
  col('5xx', (a) => num(bench(a).status_5xx)),
  col('java CPU', (a) => benchAvg(a, K.proc('java')), pct()),
  col('redis CPU', (a) => benchAvg(a, K.proc('redis-server')), pct()),
  col('machine CPU', machine, pct()),
  col('swap', (a) => benchAvg(a, K.swap), pct()),
  col('loadgen CPU', loadgen, pct()),
  col('RDS CPU', (a) => benchAvg(a, K.dbcpu), pct()),
];

export default function Table({ picked, onToggle }) {
  const [sort, setSort] = useState(null);   // { i, dir } or null for the natural order
  const rows = useMemo(() => {
    if (!sort) return everyAttempt;
    const { get } = COLS[sort.i];
    return [...everyAttempt].sort((a, b) => {
      const x = get(a), y = get(b);
      if (x == null) return 1;
      if (y == null) return -1;
      return (x < y ? -1 : x > y ? 1 : 0) * sort.dir;
    });
  }, [sort]);
  // ascending, then descending, then back to the natural order
  const clickHead = (i) => setSort((s) => !s || s.i !== i ? { i, dir: 1 } : s.dir === 1 ? { i, dir: -1 } : null);

  return (
    <div className="tablebox">
      <div className="tablescroll">
        <table>
          <thead>
            <tr>
              <th className="pickcol" />
              {COLS.map((c, i) => (
                <th key={c.name} className={i < 3 ? 'left' : undefined} onClick={() => clickHead(i)} aria-sort={sort && sort.i === i ? (sort.dir === 1 ? 'ascending' : 'descending') : 'none'}>
                  {c.name}<span className="arrow">{sort && sort.i === i ? (sort.dir === 1 ? '↑' : '↓') : ''}</span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((a) => (
              <tr key={key(a)} style={{ '--v': a.run.color }} onClick={() => onToggle(key(a))}>
                <td className="pickcol">
                  <label className="row" onClick={(e) => e.stopPropagation()}>
                    <input type="checkbox" className="tick" checked={picked.some((p) => p.k === key(a))} onChange={() => onToggle(key(a))} aria-label={`${a.run.label} ${a.vus} users`} />
                    <span className="box" aria-hidden="true"><svg viewBox="0 0 12 12" width="12" height="12"><path d="M2.5 6.5l2.5 2.5 4.5-5.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" /></svg></span>
                  </label>
                </td>
                {COLS.map((c, i) => <td key={c.name} className={i < 3 ? 'left' : undefined}>{c.fmt(c.get(a), a)}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="hint">Click a row to put it on the chart. CPU and swap are the average of the 1 minute CloudWatch points inside the bench. 200% CPU means both cores.</p>
    </div>
  );
}
