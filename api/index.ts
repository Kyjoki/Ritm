import type { IncomingMessage, ServerResponse } from 'node:http';
import { createApp } from '../server/index.ts';

// Reuse the app and its connection pool. Durable state lives in PostgreSQL.
let instance: ReturnType<typeof createApp> | undefined;

export default function handler(request: IncomingMessage, response: ServerResponse) {
  try {
    instance ??= createApp({ seed: false });
    instance.app(request, response);
  } catch {
    console.error('Ritm initialization failed. Check server environment configuration.');
    response.writeHead(503, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    response.end(
      JSON.stringify({
        error: 'Сервер ещё не настроен. Проверьте конфигурацию приложения.',
        code: 'SERVER_NOT_CONFIGURED',
      }),
    );
  }
}
