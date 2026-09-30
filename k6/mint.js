// Mint load test: every VU is a user running one loop, forever.
//
//   Each iteration: if the shared file list has files, upload with UPLOAD_CHANCE (2.6%), else download.
//   If the list is empty the user uploads.
//   Upload   = POST upload link -> sleep (stands in for the S3 PUT) -> PATCH confirm -> add to the file list.
//   Download = claim a random file from the list -> GET it.
//
// The file list lives in the local Redis on the load-gen box (see load-file-list.sh) so all VUs share it.
//   pool  SET   codes currently listed
//   left  HASH  code -> downloads remaining
//   exp   HASH  code -> expiry (epoch ms)
//   gc    ZSET  code -> expiry + grace (epoch ms); entries past their score are swept
//
// Rules:
//   * Download count is random 15..60. The claim that takes it to 0 removes the file immediately.
//   * An expired file stays listed for EXPIRED_GRACE_MS (2 min) so users keep hitting it (404), then it is removed.
//     Hits on expired files do not use up the download count.
//
// The backend's mint.cap.* rate limits must be raised: every VU shares one IP, and the per-user (cookie)
// caps would otherwise trip on a long loop.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';
import redis from 'k6/x/redis';

const BASE_URL = __ENV.BASE_URL || 'http://mint-bench-sql.dhiren.xyz';
const REDIS_URL = __ENV.REDIS_URL || 'redis://127.0.0.1:6379';
const UPLOAD_CHANCE = Number(__ENV.UPLOAD_CHANCE || 0.026);
const UPLOAD_WAIT_MIN_S = Number(__ENV.UPLOAD_WAIT_MIN_S || 1);
const UPLOAD_WAIT_MAX_S = Number(__ENV.UPLOAD_WAIT_MAX_S || 3);
const THINK_MS = Number(__ENV.THINK_MS || 0);
const EXPIRED_GRACE_MS = 2 * 60 * 1000;
// Clock skew between this box and the backend: a hit this close to expiry may go either way.
const EXPIRY_SLACK_MS = 2000;

// Same mix as the RDS seed: an equal third each.
const EXPIRIES = [
  { name: 'MINUTES15', ms: 15 * 60 * 1000 },
  { name: 'MINUTES30', ms: 30 * 60 * 1000 },
  { name: 'HOURS24', ms: 24 * 60 * 60 * 1000 },
];

const STAGES = __ENV.STAGES ? JSON.parse(__ENV.STAGES) : [
  { duration: '1m', target: 20 },
  { duration: '30s', target: 50 }, { duration: '3m', target: 50 },
  { duration: '30s', target: 100 }, { duration: '3m', target: 100 },
  { duration: '30s', target: 200 }, { duration: '3m', target: 200 },
  { duration: '30s', target: 400 }, { duration: '3m', target: 400 },
  { duration: '1m', target: 0 },
];

export const options = {
  scenarios: {
    users: { executor: 'ramping-vus', startVUs: 0, stages: STAGES, gracefulRampDown: '30s' },
  },
  summaryTrendStats: ['med', 'p(95)', 'p(99)', 'avg', 'max'],
  thresholds: {
    'http_req_duration{name:upload}': ['p(95)<200', 'p(99)<600'],
    'http_req_duration{name:confirm}': ['p(95)<200', 'p(99)<600'],
    'http_req_duration{name:download}': ['p(95)<200', 'p(99)<600'],
    'http_req_duration{name:download_expired}': ['p(95)<200', 'p(99)<600'],
    server_errors: ['rate<0.01'],
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
};

const serverErrors = new Rate('server_errors');
const emptyListUploads = new Counter('empty_list_uploads');
const expiredHits = new Counter('expired_hits');

const client = new redis.Client(REDIS_URL);

// Sweeps entries past their grace window, picks a random listed file and, if it is still live,
// takes one download from it, removing it at zero. Returns false when the list is empty,
// else {code, expired(0|1), expiresAtMs}.
const CLAIM = `
local now = tonumber(ARGV[1])
local dead = redis.call('ZRANGEBYSCORE', 'gc', '-inf', now, 'LIMIT', 0, 100)
for _, c in ipairs(dead) do
  redis.call('SREM', 'pool', c)
  redis.call('HDEL', 'left', c)
  redis.call('HDEL', 'exp', c)
  redis.call('ZREM', 'gc', c)
end
local code = redis.call('SRANDMEMBER', 'pool')
if not code then return false end
local exp = tonumber(redis.call('HGET', 'exp', code))
if now >= exp then return {code, 1, exp} end
local left = redis.call('HINCRBY', 'left', code, -1)
if left <= 0 then
  redis.call('SREM', 'pool', code)
  redis.call('HDEL', 'left', code)
  redis.call('HDEL', 'exp', code)
  redis.call('ZREM', 'gc', code)
end
return {code, 0, exp}
`;

const ADD = `
redis.call('SADD', 'pool', ARGV[1])
redis.call('HSET', 'left', ARGV[1], ARGV[2])
redis.call('HSET', 'exp', ARGV[1], ARGV[3])
redis.call('ZADD', 'gc', tonumber(ARGV[3]) + tonumber(ARGV[4]), ARGV[1])
return 1
`;

const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };

function randInt(min, max) {
  return Math.floor(min + Math.random() * (max - min + 1));
}

async function upload() {
  const expiry = EXPIRIES[randInt(0, EXPIRIES.length - 1)];

  const created = http.post(`${BASE_URL}/api/v1/file/upload`, JSON.stringify({
    expiryDuration: expiry.name,
    fileName: `f${__VU}-${__ITER}.bin`,
    contentType: 'application/octet-stream',
    contentSize: randInt(1, 5 * 1024 * 1024),
  }), { ...JSON_HEADERS, tags: { name: 'upload' } });
  serverErrors.add(created.status >= 500);
  const link = created.status === 201 ? created.json('data') : null;
  check(created, { 'upload link 201': (r) => r.status === 201 });
  if (!link) return;

  sleep(UPLOAD_WAIT_MIN_S + Math.random() * (UPLOAD_WAIT_MAX_S - UPLOAD_WAIT_MIN_S));

  const confirmed = http.patch(`${BASE_URL}/api/v1/file`, JSON.stringify({
    fileKey: link.fileKey,
    fileCode: link.fileCode,
  }), { ...JSON_HEADERS, tags: { name: 'confirm' } });
  serverErrors.add(confirmed.status >= 500);
  const ok = check(confirmed, { 'confirm 200': (r) => r.status === 200 });
  if (!ok) return;

  await client.sendCommand('EVAL', ADD, 0,
    link.fileCode, String(randInt(15, 60)), String(Date.now() + expiry.ms), String(EXPIRED_GRACE_MS));
}

function download(claim) {
  const [code, expired, expiresAt] = claim;
  const nearExpiry = Math.abs(Date.now() - expiresAt) < EXPIRY_SLACK_MS;
  const expectedStatuses = nearExpiry ? http.expectedStatuses(200, 404)
    : expired ? http.expectedStatuses(404) : http.expectedStatuses(200);

  const res = http.get(`${BASE_URL}/api/v1/file/${code}`, {
    tags: { name: expired ? 'download_expired' : 'download' },
    responseCallback: expectedStatuses,
  });
  serverErrors.add(res.status >= 500);
  if (expired) expiredHits.add(1);

  check(res, {
    'download as expected': (r) => nearExpiry ? (r.status === 200 || r.status === 404)
      : expired ? r.status === 404 : r.status === 200,
  });
}

export default async function () {
  let claim = null;
  if (Math.random() >= UPLOAD_CHANCE) {
    claim = await client.sendCommand('EVAL', CLAIM, 0, String(Date.now()));
    if (!claim) emptyListUploads.add(1);
  }

  if (claim) download(claim);
  else await upload();

  if (THINK_MS > 0) sleep(THINK_MS / 1000);
}
