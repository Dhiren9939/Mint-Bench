// the data from build.py, and the helpers every part of the dashboard uses
import raw from '../data.json';
import { RC } from '../theme.js';

export const RUNS = raw.runs;

RUNS.forEach((r, i) => {
  r.i = i;
  r.color = RC[i % RC.length];
  r.byUsers = [...r.attempts].sort((x, y) => x.vus - y.vus);
  r.byUsers.forEach((a) => { a.run = r; });
  r.best = r.byUsers.filter((a) => a.result === 'pass').pop();
  r.firstFail = r.byUsers.find((a) => a.result === 'fail' && (!r.best || a.vus > r.best.vus));
});

export const everyAttempt = RUNS.flatMap((r) => r.byUsers);
export const MIN_VUS = Math.min(...everyAttempt.map((a) => a.vus));
export const MAX_VUS = Math.max(...everyAttempt.map((a) => a.vus));
export const lastRun = RUNS[RUNS.length - 1];
export const arms = [...new Set(RUNS.map((r) => r.arm))];

export const key = (a) => `${a.run.i}:${a.vus}`;
export const attemptOf = (k) => { const [i, v] = k.split(':'); return RUNS[i].attempts.find((a) => String(a.vus) === v); };

// the numbers in the k6 stats are strings
export const bench = (a, name = 'ALL') => a.stats.find((r) => r.phase === 'bench' && r.name === name) || {};
export const f = (v, d = 1) => (v === '' || v == null || Number.isNaN(Number(v))) ? '-' : Number(v).toFixed(d);
export const ms = (v) => (v === '' || v == null) ? '-' : Number(v) >= 1000 ? (Number(v) / 1000).toFixed(2) + ' s' : Number(v).toFixed(Number(v) < 10 ? 1 : 0) + ' ms';
export const num = (v) => (v === '' || v == null || Number.isNaN(Number(v))) ? null : Number(v);

// average of a CloudWatch series inside the bench
export function benchAvg(a, k) {
  const s = a.metrics[k];
  if (!s) return null;
  const from = a.warmup_s, to = a.warmup_s + a.bench_s;
  const v = s.filter(([t]) => t >= from - 30 && t < to).map((p) => p[1]).filter((x) => x != null);
  return v.length ? v.reduce((x, y) => x + y, 0) / v.length : null;
}

export const K = {
  user: 'backend|cpu_usage_user|cpu=cpu-total|average', sys: 'backend|cpu_usage_system|cpu=cpu-total|average',
  steal: 'backend|cpu_usage_steal|cpu=cpu-total|average', mem: 'backend|mem_used_percent||average',
  swap: 'backend|swap_used_percent||average', tcp: 'backend|netstat_tcp_established||average',
  proc: (p) => `backend|procstat_cpu_usage|exe=${p};process_name=${p}|average`,
  rss: (p) => `backend|procstat_memory_rss|exe=${p};process_name=${p}|average`,
  lgu: 'loadgen|cpu_usage_user|cpu=cpu-total|average', lgs: 'loadgen|cpu_usage_system|cpu=cpu-total|average',
  lgm: 'loadgen|mem_used_percent||average',
  dbcpu: 'db|CPUUtilization||average', dbconn: 'db|DatabaseConnections||average',
  dbw: 'db|WriteIOPS||average', dbr: 'db|ReadIOPS||average',
};
export const machine = (a) => { const u = benchAvg(a, K.user), s = benchAvg(a, K.sys); return u == null ? null : u + (s || 0); };
export const loadgen = (a) => { const u = benchAvg(a, K.lgu), s = benchAvg(a, K.lgs); return u == null ? null : u + (s || 0); };

// time series of one attempt. tl drops zeros (a latency of 0 means no requests), tlAny keeps them
export const tl = (a, name, k) => { const t = a.timeline[name]; return t ? t.t.map((x, i) => ({ x: x + 5, y: t[k][i] })).filter((p) => p.y != null && p.y > 0) : []; };
export const tlAny = (a, name, k) => { const t = a.timeline[name]; return t ? t.t.map((x, i) => ({ x: x + 5, y: t[k][i] })).filter((p) => p.y != null) : []; };
export const ms1 = (a, k, scale = 1) => (a.metrics[k] || []).filter((p) => p[1] != null).map(([t, v]) => ({ x: t, y: v * scale }));
export const sum = (p, q) => p.map((pt) => { const o = q.find((z) => z.x === pt.x); return { x: pt.x, y: pt.y + (o ? o.y : 0) }; });
