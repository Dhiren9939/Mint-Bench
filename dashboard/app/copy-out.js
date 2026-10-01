// puts the built single file at the root of the repo, where the old dashboard was
import { copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const from = fileURLToPath(new URL('./dist/index.html', import.meta.url));
const to = fileURLToPath(new URL('../../dashboard.html', import.meta.url));
copyFileSync(from, to);
console.log('wrote', to);
