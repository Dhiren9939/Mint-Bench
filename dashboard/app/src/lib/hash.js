// the view lives in the address, so it can be bookmarked or sent: #x=users&m=p99&p=0:1420,1:4687
import { METRIC, available } from './metrics.js';
import { RUNS, lastRun, key, attemptOf } from './data.js';
import { PICK } from '../theme.js';

export function readHash() {
  const q = new URLSearchParams(location.hash.slice(1));
  const x = q.get('x') === 'time' ? 'time' : 'users';
  let m = q.get('m');
  if (!METRIC[m] || !available(METRIC[m], x)) m = 'p99';
  let keys = (q.get('p') || '').split(',').filter((k) => k && /^\d+:\d+$/.test(k) && RUNS[k.split(':')[0]] && attemptOf(k));
  if (!q.has('p')) {
    const first = RUNS[0];
    keys = [first.best, lastRun.best, lastRun.firstFail].filter(Boolean).map(key);
  }
  keys = [...new Set(keys)].slice(0, PICK.length);
  return { x, m, picked: keys.map((k, i) => ({ k, color: PICK[i] })) };
}

export function writeHash(x, m, picked) {
  const q = new URLSearchParams({ x, m, p: picked.map((p) => p.k).join(',') });
  history.replaceState(null, '', '#' + q.toString().replace(/%3A/g, ':').replace(/%2C/g, ','));
}
