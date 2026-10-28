import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const routes = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/index.html', ['index.html', 'text/html; charset=utf-8']],
  ...[
    'preview.css',
    'preview.js',
    'sections-day-calendar.js',
    'sections-habits-finance.js',
    'sections-assistant-settings.js',
  ].map((name) => [
    '/' + name,
    [name, name.endsWith('.css') ? 'text/css; charset=utf-8' : 'text/javascript; charset=utf-8'],
  ]),
]);
const server = createServer(async (request, response) => {
  const path = request.url?.split('?')[0];
  const route = routes.get(path);
  if (!['GET', 'HEAD'].includes(request.method) || !route) {
    response.writeHead(404).end();
    return;
  }
  try {
    const body = await readFile(new URL('./' + route[0], import.meta.url));
    response.writeHead(200, {
      'Content-Type': route[1],
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy':
        "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    });
    response.end(request.method === 'HEAD' ? undefined : body);
  } catch {
    response.writeHead(503).end('Preview is being prepared.');
  }
});
server.listen(Number(process.env.RITM_PREVIEW_PORT || 0), '127.0.0.1', () => {
  console.log(`Ritm iPhone design preview: http://127.0.0.1:${server.address().port}/`);
  console.log('Six-screen HTML mockup. No account, API, or production data.');
});
