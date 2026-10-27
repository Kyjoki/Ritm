import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import react from '@vitejs/plugin-react';

const root = fileURLToPath(new URL('../', import.meta.url));
const dataDir = mkdtempSync(join(tmpdir(), 'ritm-visual-preview-'));
// Only explicit local variables reach either child. Project .env files are never loaded.
const env = {
  PATH: process.env.PATH,
  Path: process.env.Path,
  SystemRoot: process.env.SystemRoot,
  TEMP: process.env.TEMP,
  TMP: process.env.TMP,
  NODE_ENV: 'development',
  DATA_DIR: dataDir,
  SEED_DEMO: 'true',
  HOST: '127.0.0.1',
  PORT: '3001',
  APP_ORIGIN: 'http://127.0.0.1:5173',
};

function runSeed() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['--import', 'tsx', 'scripts/seed-visual-preview.ts'], {
      cwd: root,
      env,
      stdio: 'inherit',
    });
    child.on('error', reject);
    child.on('exit', (code) =>
      code === 0 ? resolve() : reject(new Error(`Demo seed exited with ${code}`)),
    );
  });
}

await runSeed();
const backend = spawn(process.execPath, ['--import', 'tsx', 'server/index.ts'], {
  cwd: root,
  env,
  stdio: 'inherit',
});
backend.on('error', (error) => console.error(error.message));
const vite = await createServer({
  configFile: false,
  root,
  envDir: dataDir,
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: { '/api': 'http://127.0.0.1:3001' },
  },
});
await vite.listen();
console.log('Ritm visual preview (isolated demo): http://127.0.0.1:5173/?design-preview=1');
console.log('No production connection. Close with Ctrl+C.');
let closing = false;
async function close() {
  if (closing) return;
  closing = true;
  backend.kill();
  await vite.close();
}
backend.on('exit', () => {
  void close();
});
process.on('SIGINT', () => {
  void close();
});
process.on('SIGTERM', () => {
  void close();
});
