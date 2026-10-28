import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import type { Plugin } from 'vite';

export function liveMobilePreview(): Plugin {
  return {
    name: 'ritm-live-mobile-preview',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/__dev/mobile-preview', (_request, response, next) => {
        if (_request.method !== 'GET' && _request.method !== 'HEAD') {
          next();
          return;
        }

        response.statusCode = 200;
        response.setHeader('Cache-Control', 'no-store');
        response.setHeader('Content-Type', 'text/html; charset=utf-8');
        const previewUrl = new URL(_request.url ?? '/', 'http://localhost');
        const requestedTheme = previewUrl.searchParams.get('previewTheme');
        const themeQuery =
          requestedTheme === 'light' || requestedTheme === 'dark'
            ? `?previewTheme=${requestedTheme}`
            : '';
        response.end(`<!doctype html>
<html lang="ru">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="theme-color" content="#17161d" />
    <title>Ritm · Live Mobile Preview</title>
    <link rel="stylesheet" href="/src/styles/dev-mobile-preview.css" />
  </head>
  <body>
    <div class="preview-layout">
      <aside class="preview-controls">
        <a class="back-link" href="/#calendar">← Ritm</a>
        <p class="eyebrow">ЛОКАЛЬНЫЙ ИНСТРУМЕНТ</p>
        <h1>Live Mobile Preview</h1>
        <p class="intro">Рабочая мобильная версия Ritm в настоящем узком viewport. Изменения кода обновляются через Vite HMR.</p>

        <label class="field-label" for="device">Размер iPhone</label>
        <select id="device" aria-label="Размер iPhone">
          <option value="narrow">320 × 640</option>
          <option value="small">360 × 740</option>
          <option value="compact">375 × 667</option>
          <option value="wideCompact">390 × 844</option>
          <option value="standard" selected>Стандартный · 393 × 852</option>
          <option value="large">Большой · 430 × 932</option>
        </select>

        <span class="field-label orientation-label">Ориентация</span>
        <div class="segmented" role="group" aria-label="Ориентация телефона">
          <button type="button" data-orientation="portrait" aria-pressed="true">Вертикально</button>
          <button type="button" data-orientation="landscape" aria-pressed="false">Горизонтально</button>
        </div>

        <div class="live-status"><span aria-hidden="true"></span><div><strong>Live reload включён</strong><small>Vite HMR · локальная сборка</small></div></div>
        <a class="open-tab" href="/__dev/mobile-preview" target="_blank" rel="noopener noreferrer">Открыть preview в новой вкладке ↗</a>

        <p class="note">Это интерактивный браузерный preview. Он показывает адаптивную вёрстку, но не заменяет Safari, установленную PWA или проверку производительности на настоящем iPhone.</p>
      </aside>

      <main class="preview-stage">
        <div class="stage-heading"><div><span class="eyebrow">RITM · МОБИЛЬНЫЙ VIEWPORT</span><p id="viewport-label">393 × 852 CSS px · вертикально</p></div><span class="stage-live"><i></i> Ritm работает</span></div>
        <div class="stage-scroll">
          <div class="phone-shell" id="phone-shell" style="--screen-width:393px;--screen-height:852px">
            <div class="phone-screen">
              <div class="mock-status" aria-hidden="true"><span>9:41</span><span class="status-icons">● ● ▰</span></div>
              <iframe id="app-frame" title="Ritm в мобильном viewport" src="/${themeQuery}#calendar" allow="clipboard-read; clipboard-write; web-share"></iframe>
              <div class="mock-home" aria-hidden="true"><span></span></div>
            </div>
          </div>
        </div>
      </main>
    </div>
    <script type="module" src="/src/dev/mobile-preview-client.ts"></script>
  </body>
</html>`);
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), liveMobilePreview()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: { '/api': 'http://127.0.0.1:3001' },
  },
  build: { outDir: 'build/client', emptyOutDir: true },
});
