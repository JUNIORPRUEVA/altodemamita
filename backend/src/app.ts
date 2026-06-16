import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { authRouter } from './routes/auth.routes';
import { ownerRouter } from './routes/owner.routes';
import { syncRouter } from './routes/sync.routes';

export function createApp() {
  const app = express();

  app.use(helmet());
  app.use(cors({ origin: true, credentials: true }));
  app.use(express.json({ limit: '10mb' }));
  app.use(morgan('combined'));

  const healthHandler = (_req: express.Request, res: express.Response) => {
    res.json({ ok: true, service: 'sistema-solares-backend' });
  };

  app.get('/', healthHandler);
  app.get('/health', healthHandler);
  app.get('/api/health', healthHandler);

  app.use('/api/auth', authRouter);
  app.use('/auth', authRouter);
  app.use('/api/owner', ownerRouter);
  app.use('/owner', ownerRouter);
  app.use('/api/sync', syncRouter);
  app.use('/sync', syncRouter);
  app.use('/api/pos-sync', syncRouter);
  app.use('/pos-sync', syncRouter);

  app.use((_req, res) => {
    res.status(404).json({ error: { message: 'Ruta no encontrada.' } });
  });

  return app;
}
