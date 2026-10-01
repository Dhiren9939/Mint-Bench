import { RUNS, key, bench, f, ms } from '../lib/data.js';
import { PICK } from '../theme.js';

// every attempt of every version. Click one to put it on the chart (up to 7).
export default function Attempts({ picked, onToggle }) {
  return (
    <aside className="side">
      {RUNS.map((r) => (
        <section key={r.i}>
          <h3>{r.label}<small>{r.arm}</small></h3>
          {r.byUsers.map((a) => (
            <label key={a.vus} className="row">
              <input type="checkbox" className="tick" checked={picked.some((x) => x.k === key(a))} onChange={() => onToggle(key(a))} />
              <span className="box" aria-hidden="true">
                <svg viewBox="0 0 12 12" width="12" height="12"><path d="M2.5 6.5l2.5 2.5 4.5-5.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" /></svg>
              </span>
              <span className={`mark ${a.result}`} title={a.result} />
              <b>{a.vus.toLocaleString()}</b>
              <span className="dim">{f(bench(a).rps, 0)}/s &middot; p99 {ms(bench(a).p99_ms)}</span>
            </label>
          ))}
        </section>
      ))}
      <p className="hint">Filled circle passed, diamond failed. Up to {PICK.length} at a time.</p>
    </aside>
  );
}
