import { Body, Controller, Get, Post } from '@nestjs/common';

import { Public } from 'src/shared/decorators/public.decorator';
import { SystemConfigService } from '../../application/services/system-config.service';
import { SystemSetupDto } from '../../application/dto/system-setup.dto';
import { SystemService } from '../../application/services/system.service';

@Controller('system')
export class SystemController {
  constructor(
    private readonly systemService: SystemService,
    private readonly systemConfigService: SystemConfigService,
  ) {}

  @Public()
  @Get('config')
  getConfig() {
    return {
      readOnly: this.systemConfigService.isReadOnly(),
    };
  }

  @Public()
  @Get('status')
  getStatus() {
    return this.systemService.getStatus();
  }

  @Public()
  @Post('setup')
  setup(@Body() dto: SystemSetupDto) {
    return this.systemService.setup(dto);
  }
}