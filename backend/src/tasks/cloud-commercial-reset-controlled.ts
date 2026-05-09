type AllowedMode = 'dry-run' | 'execute';

function fail(message: string): never {
  throw new Error(message);
}

function readMode(): AllowedMode {
  const mode = (process.env.CLOUD_COMMERCIAL_RESET_MODE ?? '').trim();
  if (mode === 'dry-run' || mode === 'execute') {
    return mode;
  }
  return fail(
    'CLOUD_COMMERCIAL_RESET_MODE invalido. Usa dry-run o execute.',
  );
}

async function run(): Promise<void> {
  const enabled = (process.env.RUN_CLOUD_COMMERCIAL_RESET_TASK ?? '').trim();
  if (enabled !== 'true') {
    fail(
      'Operacion bloqueada: RUN_CLOUD_COMMERCIAL_RESET_TASK=true es obligatorio.',
    );
  }

  const mode = readMode();
  process.argv = [
    process.argv[0],
    process.argv[1],
    `--mode=${mode}`,
  ];

  await import('./cloud-commercial-reset');
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`ERROR: ${message}`);
  process.exit(1);
});
