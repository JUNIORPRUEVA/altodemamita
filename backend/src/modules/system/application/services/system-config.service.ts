import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class SystemConfigService {
  constructor(private readonly configService: ConfigService) {}

  isReadOnly(): boolean {
    return this.configService.get<boolean>('system.readOnlyMode') === true;
  }
}