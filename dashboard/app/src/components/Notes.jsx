import { useEffect, useRef } from 'react';
import { RUNS } from '../lib/data.js';

// what happened in each version, from story.txt in the run folder: first line is the heading, blank lines split paragraphs
export default function Notes({ onClose }) {
  const ref = useRef(null);
  useEffect(() => { ref.current.showModal(); }, []);
  const close = () => ref.current.close();
  return (
    <dialog ref={ref} onClose={onClose} onClick={(e) => { if (e.target === ref.current) close(); }}>
      {RUNS.filter((r) => r.story).map((r) => {
        const [head, ...parts] = r.story.trim().split(/\n\s*\n/);
        return (
          <div key={r.i}>
            <h2>{head.trim()}</h2>
            <p className="meta">{r.label}, {r.arm}, run {r.run}</p>
            {parts.map((t, i) => <p key={i}>{t.trim()}</p>)}
          </div>
        );
      })}
      <button type="button" className="btn" style={{ marginTop: 6 }} onClick={close}>Close</button>
    </dialog>
  );
}
