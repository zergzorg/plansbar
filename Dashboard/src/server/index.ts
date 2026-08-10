import express from 'express';
import { homedir } from 'node:os';
import path from 'node:path';
import { createServer as createViteServer } from 'vite';
import { PlanIndexService } from './planIndexService.js';

const DEFAULT_PORT = 5178;
const DEFAULT_STALE_DAYS = 30;

const root = process.env.PLANSBAR_ROOT ?? path.join(homedir(), 'Code');
const port = parsePort(process.env.PORT, DEFAULT_PORT);
const staleDays = parseNonNegativeInteger(
  process.env.PLANSBAR_STALE_DAYS,
  DEFAULT_STALE_DAYS
);
const isProduction = process.env.NODE_ENV === 'production';

const app = express();
const service = new PlanIndexService({
  root,
  staleDays,
  watch: true
});

app.use(express.json());

app.get('/api/snapshot', (_request, response) => {
  response.json(service.getSnapshot());
});

app.post('/api/rescan', async (_request, response, next) => {
  try {
    response.json(await service.rescan('manual'));
  } catch (error) {
    next(error);
  }
});

app.get('/api/events', (request, response) => {
  response.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive'
  });

  const sendSnapshot = (reason: string) => {
    response.write(`event: snapshot\n`);
    response.write(`data: ${JSON.stringify({ reason, snapshot: service.getSnapshot() })}\n\n`);
  };

  sendSnapshot('connected');
  const unsubscribe = service.subscribe((_snapshot, reason) => sendSnapshot(reason));
  request.on('close', unsubscribe);
});

app.use('/api', (_request, response) => {
  response.status(404).json({ ok: false, error: 'API endpoint not found' });
});

app.use((error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
  const statusCode = typeof error === 'object' && error !== null && 'statusCode' in error
    ? Number((error as { statusCode: unknown }).statusCode)
    : 500;
  const message = error instanceof Error ? error.message : 'Unexpected server error';

  response.status(Number.isInteger(statusCode) ? statusCode : 500).json({
    ok: false,
    error: message
  });
});

await service.start();

if (isProduction) {
  const clientDist = path.resolve(process.cwd(), 'dist/client');
  app.use(express.static(clientDist));
  app.get('*', (_request, response) => {
    response.sendFile(path.join(clientDist, 'index.html'));
  });
} else {
  const vite = await createViteServer({
    server: { middlewareMode: true },
    appType: 'custom'
  });
  app.use(vite.middlewares);
  app.use('*', async (request, response, next) => {
    try {
      const template = await vite.transformIndexHtml(
        request.originalUrl,
        '<!doctype html><html lang="en"><head><meta charset="UTF-8" /><meta name="viewport" content="width=device-width, initial-scale=1.0" /><meta name="theme-color" content="#efece6" /><meta name="description" content="Local read-only index of engineering plans" /><title>PlansBar Dashboard</title></head><body><div id="root"></div><script type="module" src="/src/client/main.tsx"></script></body></html>'
      );
      response.status(200).set({ 'Content-Type': 'text/html' }).end(template);
    } catch (error) {
      vite.ssrFixStacktrace(error as Error);
      next(error);
    }
  });
}

const server = app.listen(port, () => {
  console.log(`PlansBar Dashboard: http://localhost:${port}`);
  console.log(`Scanning root: ${root}`);
  console.log(`Stale threshold: ${staleDays} days`);
});

const shutdown = async () => {
  await service.stop();
  server.close(() => {
    process.exit(0);
  });
};

process.on('SIGINT', () => {
  void shutdown();
});

process.on('SIGTERM', () => {
  void shutdown();
});

function parsePort(value: string | undefined, fallback: number): number {
  const parsed = Number(value ?? fallback);
  return Number.isInteger(parsed) && parsed > 0 && parsed <= 65_535 ? parsed : fallback;
}

function parseNonNegativeInteger(value: string | undefined, fallback: number): number {
  const parsed = Number(value ?? fallback);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : fallback;
}
