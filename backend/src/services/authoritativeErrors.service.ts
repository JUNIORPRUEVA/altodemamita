export class AuthoritativeError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly httpStatus = 400,
  ) {
    super(message);
    this.name = 'AuthoritativeError';
  }
}

export function authoritativeErrorResponse(error: unknown) {
  if (error instanceof AuthoritativeError) {
    return {
      status: error.httpStatus,
      body: { error: { code: error.code, message: error.message } },
    };
  }

  if (error && typeof error === 'object' && 'code' in error) {
    const code = String((error as { code?: unknown }).code ?? '');
    if (code === 'P2002') {
      return {
        status: 409,
        body: {
          error: {
            code: 'CONCURRENT_WRITE_CONFLICT',
            message: 'La operacion compite con otro cambio ya confirmado.',
          },
        },
      };
    }
  }

  return {
    status: 500,
    body: {
      error: {
        code: 'AUTHORITATIVE_OPERATION_FAILED',
        message: 'No se pudo completar la operacion autoritativa.',
      },
    },
  };
}
