// What can be drawn. scalar is one number per attempt (the bench part), used when users are on the x axis.
// series is the value over time inside one attempt. limit is the pass line, max is how far the axis goes at least.
import { bench, num, benchAvg, K, tl, tlAny, ms1, sum, machine, loadgen } from './data.js';

const stat = (k) => (a) => num(bench(a)[k]);
const avg = (k, scale = 1) => (a) => { const v = benchAvg(a, k); return v == null ? null : v * scale; };

export const METRICS = [
  { id: 'p50', group: 'Latency', name: 'p50', unit: 'ms', scalar: stat('p50_ms'), series: (a) => tl(a, 'ALL', 'p50') },
  { id: 'p95', group: 'Latency', name: 'p95', unit: 'ms', scalar: stat('p95_ms'), series: (a) => tl(a, 'ALL', 'p95'), limit: 200 },
  { id: 'p99', group: 'Latency', name: 'p99', unit: 'ms', scalar: stat('p99_ms'), series: (a) => tl(a, 'ALL', 'p99'), limit: 600 },
  { id: 'rps', group: 'Traffic', name: 'Requests/s', unit: 'requests per second', scalar: stat('rps'), series: (a) => tlAny(a, 'ALL', 'rps'), expected: 0.2 },
  { id: 'users', group: 'Traffic', name: 'Users', unit: 'users', series: (a) => tlAny(a, 'ALL', 'vus') },
  { id: 'cpu', group: 'Backend', name: 'CPU', unit: '% of the machine', scalar: machine, series: (a) => sum(ms1(a, K.user), ms1(a, K.sys)), max: 100 },
  { id: 'java', group: 'Backend', name: 'java', unit: '% of one core', scalar: avg(K.proc('java')), series: (a) => ms1(a, K.proc('java')), max: 200 },
  { id: 'redis', group: 'Backend', name: 'redis', unit: '% of one core', scalar: avg(K.proc('redis-server')), series: (a) => ms1(a, K.proc('redis-server')) },
  { id: 'mem', group: 'Backend', name: 'Memory', unit: '% used', scalar: avg(K.mem), series: (a) => ms1(a, K.mem), max: 100 },
  { id: 'swap', group: 'Backend', name: 'Swap', unit: '% used', scalar: avg(K.swap), series: (a) => ms1(a, K.swap) },
  { id: 'rss', group: 'Backend', name: 'java memory', unit: 'MB', scalar: avg(K.rss('java'), 1 / 1048576), series: (a) => ms1(a, K.rss('java'), 1 / 1048576) },
  { id: 'lg', group: 'Load generator', name: 'CPU', unit: '% of the machine', scalar: loadgen, series: (a) => sum(ms1(a, K.lgu), ms1(a, K.lgs)), max: 100 },
  { id: 'db', group: 'RDS', name: 'CPU', unit: '%', scalar: avg(K.dbcpu), series: (a) => ms1(a, K.dbcpu), max: 100 },
  { id: 'dbconn', group: 'RDS', name: 'Connections', unit: 'connections', scalar: avg(K.dbconn), series: (a) => ms1(a, K.dbconn) },
];
export const METRIC = Object.fromEntries(METRICS.map((m) => [m.id, m]));
export const GROUPS = [...new Set(METRICS.map((m) => m.group))];
// can the metric be drawn with users on x (a number per attempt) or over time (a series)
export const available = (m, x) => x === 'users' ? !!m.scalar : !!m.series;
