import { useEffect, useState } from 'react';
import { PICK } from './theme.js';
import { METRICS, METRIC, GROUPS, available } from './lib/metrics.js';
import { readHash, writeHash } from './lib/hash.js';
import ChartView from './components/ChartView.jsx';
import Attempts from './components/Attempts.jsx';
import Table from './components/Table.jsx';
import Notes from './components/Notes.jsx';

export default function App() {
  const [init] = useState(readHash);
  const [x, setX] = useState(init.x);
  const [m, setM] = useState(init.m);
  const [picked, setPicked] = useState(init.picked);
  const [notes, setNotes] = useState(false);
  useEffect(() => writeHash(x, m, picked), [x, m, picked]);

  // by users and over time can draw different things, keep the metric that works
  const useX = (nx) => { setX(nx); if (!available(METRIC[m], nx)) setM('p99'); };
  // up to 7 attempts, each keeps its colour while it is picked, the oldest one drops off
  const toggle = (k) => setPicked((cur) => {
    if (cur.some((p) => p.k === k)) return cur.filter((p) => p.k !== k);
    const next = cur.length >= PICK.length ? cur.slice(1) : cur;
    return [...next, { k, color: PICK.find((c) => !next.some((p) => p.color === c)) }];
  });

  return (
    <div className="app">
      <div className="top">
        <h1>Mint bench</h1>
        <div className="seg" role="group" aria-label="X axis">
          <button type="button" className={x === 'users' ? 'on' : ''} onClick={() => useX('users')}>By users</button>
          <button type="button" className={x === 'time' ? 'on' : ''} onClick={() => useX('time')}>Over time</button>
        </div>
        <span className="spacer" />
        <button type="button" className="btn" onClick={() => setNotes(true)}>Notes</button>
      </div>
      <div className="metrics">
        {GROUPS.map((g) => (
          <div key={g} className="mg">
            <small>{g}</small>
            {METRICS.filter((k) => k.group === g).map((k) => (
              <button key={k.id} type="button" className={k.id === m ? 'pillbtn on' : 'pillbtn'} disabled={!available(k, x)} onClick={() => setM(k.id)}>{k.name}</button>
            ))}
          </div>
        ))}
      </div>
      <div className="main">
        <ChartView metric={METRIC[m]} x={x} picked={picked} />
        <Attempts picked={picked} onToggle={toggle} />
      </div>
      <Table picked={picked} onToggle={toggle} />
      {notes && <Notes onClose={() => setNotes(false)} />}
    </div>
  );
}
