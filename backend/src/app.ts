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

  app.get('/health', (_req, res) => {
    res.json({ ok: true, service: 'sistema-solares-backend' });
  });

  app.use('/api/auth', authRouter);
  app.use('/api/owner', ownerRouter);
  app.use('/api/pos-sync', syncRouter);

  app.use((_req, res) => {
    res.status(404).json({ error: { message: 'Ruta no encontrada.' } });
  });

  return app;
}
