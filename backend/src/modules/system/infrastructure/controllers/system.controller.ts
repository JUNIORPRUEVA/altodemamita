import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  UnauthorizedException,
} from '@nestjs/common';

import { Public } from 'src/shared/decorators/public.decorator';
import { AllowInReadOnly } from 'src/shared/decorators/allow-in-read-only.decorator';
import { SystemConfigService } from '../../application/services/system-config.service';
import { SystemSetupDto } from '../../application/dto/system-setup.dto';
import { SystemService } from '../../application/services/system.service';

const RESET_ALL_ADMIN_KEY = 'RESET123';

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

  @Public()
  @Post('reset-all')
  @AllowInReadOnly()
  @HttpCode(HttpStatus.OK)
  resetAll(@Headers('x-admin-key') adminKey?: string) {
    if (adminKey?.trim() !== RESET_ALL_ADMIN_KEY) {
      throw new UnauthorizedException('Admin key invalida.');
    }

    return this.systemService.resetAll();
  }
}