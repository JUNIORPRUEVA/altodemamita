import { Global, Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

import { AuthModule } from '../auth/auth.module';

import { RealtimeGateway } from './realtime.gateway';
import { RealtimeEventsService } from './realtime-events.service';

@Global()
@Module({
  imports: [ConfigModule, AuthModule],
  providers: [RealtimeGateway, RealtimeEventsService],
  exports: [RealtimeGateway, RealtimeEventsService],
})
export class RealtimeModule {}