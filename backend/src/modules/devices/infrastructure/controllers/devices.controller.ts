import { Body, Controller, Get, Headers, HttpCode, HttpStatus, Post } from '@nestjs/common';

import { CurrentUser, AuthenticatedUser } from 'src/shared/decorators/current-user.decorator';
import { AllowDeviceWriteBypass } from 'src/shared/decorators/allow-device-write-bypass.decorator';
import { DeviceAuthorizationService } from 'src/shared/services/device-authorization.service';
import { ClaimPrimaryDeviceDto } from '../../application/dto/claim-primary-device.dto';
import { RegisterDeviceDto } from '../../application/dto/register-device.dto';
import { RevokeDeviceDto } from '../../application/dto/revoke-device.dto';

@Controller('devices')
export class DevicesController {
  constructor(
    private readonly deviceAuthorizationService: DeviceAuthorizationService,
  ) {}

  @Post('register')
  @AllowDeviceWriteBypass()
  @HttpCode(HttpStatus.OK)
  register(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RegisterDeviceDto,
    @Headers('x-device-id') headerDeviceId?: string,
  ) {
    return this.deviceAuthorizationService.registerDevice({
      userId: user.sub,
      clientType: user.type,
      roles: user.roles,
      deviceId: dto.device_id ?? headerDeviceId,
      deviceName: dto.device_name,
      platform: dto.platform,
    });
  }

  @Get('current')
  getCurrent(
    @CurrentUser() user: AuthenticatedUser,
    @Headers('x-device-id') headerDeviceId?: string,
  ) {
    return this.deviceAuthorizationService.resolveCurrentAccess({
      userId: user.sub,
      clientType: user.type,
      roles: user.roles,
      deviceId: headerDeviceId,
      autoRegisterDesktop: false,
    });
  }

  @Post('claim-primary')
  @AllowDeviceWriteBypass()
  @HttpCode(HttpStatus.OK)
  claimPrimary(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: ClaimPrimaryDeviceDto,
    @Headers('x-device-id') headerDeviceId?: string,
  ) {
    return this.deviceAuthorizationService.claimPrimary({
      userId: user.sub,
      clientType: user.type,
      roles: user.roles,
      deviceId: dto.device_id ?? headerDeviceId,
      deviceName: dto.device_name,
      platform: dto.platform,
    });
  }

  @Post('revoke')
  @AllowDeviceWriteBypass()
  @HttpCode(HttpStatus.OK)
  revoke(@CurrentUser() user: AuthenticatedUser, @Body() dto: RevokeDeviceDto) {
    return this.deviceAuthorizationService.revokeDevice(user.sub, dto.device_id);
  }
}