import { Controller, Get } from '@nestjs/common';

import { Public } from 'src/shared/decorators/public.decorator';

@Controller()
export class HealthController {
  @Public()
  @Get('health')
  health() {
    return {
      ok: true,
      timestamp: new Date().toISOString(),
    };
  }

  @Public()
  @Get('ping')
  ping() {
    return {
      ok: true,
      timestamp: new Date().toISOString(),
    };
  }
}
