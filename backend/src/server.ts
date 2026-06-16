import { bootstrapUsers } from './bootstrap';
import { config, validateConfig } from './config';
import { createApp } from './app';

async function main() {
  validateConfig();
  await bootstrapUsers();

  const app = createApp();
  app.listen(config.port, () => {
    console.log(`Sistema Solares backend escuchando en puerto ${config.port}`);
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
