import { spawn } from 'node:child_process';
import { mkdtempSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import react from '@vitejs/plugin-react';
import { createApp } from '../server/index.ts';
import { liveMobilePreview } from '../vite.config.ts';

const root = fileURLToPath(new URL('../', import.meta.url));
const dataDir = mkdtempSync(join(tmpdir(), 'ritm-visual-preview-'));
const previewPort = Number(process.env.RITM_PREVIEW_PORT ?? 5176);
const apiPort = Number(process.env.RITM_PREVIEW_API_PORT ?? 3002);
// Only explicit local variables reach the API and seed process. Project .env files are never loaded.
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
  PORT: String(apiPort),
  APP_ORIGIN: `http://127.0.0.1:${previewPort}`,
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
const backend = createApp({ dataDir, seed: true, env });
const api = backend.app.listen(apiPort, '127.0.0.1', () => {
  console.log(`Ritm server ready on port ${apiPort}.`);
});
const vite = await createServer({
  configFile: false,
  root,
  cacheDir: join(dataDir, 'vite-cache'),
  envDir: dataDir,
  plugins: [react(), liveMobilePreview()],
  server: {
    host: '127.0.0.1',
    port: previewPort,
    strictPort: true,
    proxy: { '/api': `http://127.0.0.1:${apiPort}` },
    fs: { allow: [root, realpathSync(join(root, 'node_modules'))] },
  },
});
await vite.listen();
console.log(
  `Ritm visual preview (isolated demo): http://127.0.0.1:${previewPort}/?design-preview=1`,
);
console.log('No production connection. Close with Ctrl+C.');
let closing = false;
async function close() {
  if (closing) return;
  closing = true;
  await vite.close();
  await new Promise((resolve) => api.close(resolve));
  await backend.close();
}
process.on('SIGINT', () => {
  void close();
});
process.on('SIGTERM', () => {
  void close();
});
