import { Body, Controller, Get, Headers, HttpCode, HttpStatus, Post } from '@nestjs/common';

import { CurrentUser, AuthenticatedUser } from 'src/shared/decorators/current-user.decorator';
import { AllowDeviceWriteBypass } from 'src/shared/decorators/allow-device-write-bypass.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { DeviceAuthorizationService } from 'src/shared/services/device-authorization.service';
import { ActivateDeviceDto } from '../../application/dto/activate-device.dto';
import { ClaimPrimaryDeviceDto } from '../../application/dto/claim-primary-device.dto';
import { RegisterDeviceDto } from '../../application/dto/register-device.dto';
import { RevokeDeviceDto } from '../../application/dto/revoke-device.dto';

@Controller('devices')
export class DevicesController {
  constructor(
    private readonly deviceAuthorizationService: DeviceAuthorizationService,
  ) {}

  @Get()
  @RequirePermissions(PERMISSIONS.systemConfig)
  list(@CurrentUser() user: AuthenticatedUser) {
    return this.deviceAuthorizationService.listAuthorizedDevices(user.sub);
  }

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
  @AllowDeviceWriteBypass()
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
  @RequirePermissions(PERMISSIONS.systemConfig)
  @HttpCode(HttpStatus.OK)
  claimPrimary(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: ClaimPrimaryDeviceDto,
    @Headers('x-device-id') headerDeviceId?: string,
  ) {
    return this.deviceAuthorizationService.activateSingleDevice({
      userId: user.sub,
      actorType: user.type,
      deviceId: (dto.device_id ?? headerDeviceId) ?? '',
      deviceName: dto.device_name,
      platform: dto.platform,
    });
  }

  @Post('activate')
  @AllowDeviceWriteBypass()
  @HttpCode(HttpStatus.OK)
  activate(@CurrentUser() user: AuthenticatedUser, @Body() dto: ActivateDeviceDto) {
    const resolvedDeviceId = dto.resolvedDeviceId;
    return this.deviceAuthorizationService.activateSingleDevice({
      userId: user.sub,
      actorType: user.type,
      roles: user.roles,
      deviceId: resolvedDeviceId,
      deviceName: dto.resolvedDeviceName,
      platform: dto.platform,
    });
  }

  @Post('revoke')
  @AllowDeviceWriteBypass()
  @RequirePermissions(PERMISSIONS.systemConfig)
  @HttpCode(HttpStatus.OK)
  revoke(@CurrentUser() user: AuthenticatedUser, @Body() dto: RevokeDeviceDto) {
    return this.deviceAuthorizationService.revokeDevice(user.sub, dto.device_id);
  }
}