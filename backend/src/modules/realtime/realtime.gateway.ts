import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Server, Socket } from 'socket.io';
import { UserPresenceService } from 'src/shared/services/user-presence.service';
import { isAllowedPanelOrigin } from 'src/shared/utils/panel-origin.util';

type RealtimeUser = {
  sub: string;
  roles: string[];
  permissions: string[];
  type: 'desktop' | 'panel';
};

@WebSocketGateway({
  namespace: '/realtime',
  cors: false,
})
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly userPresenceService: UserPresenceService,
  ) {}

  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(RealtimeGateway.name);

  handleConnection(client: Socket): void {
    try {
      this.validateOrigin(client);
      const token = client.handshake.auth?.token;
      if (typeof token !== 'string' || token.trim().length == 0) {
        throw new UnauthorizedException('Token WebSocket requerido.');
      }

      const user = this.jwtService.verify<RealtimeUser>(token, {
        secret: this.configService.getOrThrow<string>('jwt.secret'),
      });

      client.data.user = user;
      this.userPresenceService.markConnected(user.sub, user.type, client.id);
      client.join(this.buildUserRoom(user.sub));
      client.join(this.buildClientTypeRoom(user.type));
      for (const role of user.roles) {
        client.join(this.buildRoleRoom(role));
      }
      for (const permission of user.permissions) {
        client.join(this.buildPermissionRoom(permission));
      }

      this.logger.debug(`Cliente WebSocket autenticado: ${client.id} -> ${user.sub}`);
    } catch (_error) {
      this.logger.warn(`Conexion WebSocket rechazada: ${client.id}`);
      client.disconnect(true);
      return;
    }

    client.emit('realtime.connected', {
      clientId: client.id,
      connectedAt: new Date().toISOString(),
    });
  }

  handleDisconnect(client: Socket): void {
    this.userPresenceService.markDisconnected(client.id);
    this.logger.debug(`Cliente WebSocket desconectado: ${client.id}`);
  }

  emitToRooms(event: string, payload: Record<string, unknown>, rooms: string[]): void {
    const uniqueRooms = [...new Set(rooms.filter((room) => room.trim().length > 0))];
    if (uniqueRooms.length === 0) {
      return;
    }

    let operator = this.server.to(uniqueRooms[0]);
    for (const room of uniqueRooms.slice(1)) {
      operator = operator.to(room);
    }

    operator.emit(event, {
      ...payload,
      emittedAt: payload.emittedAt ?? new Date().toISOString(),
    });
  }

  buildUserRoom(userId: string): string {
    return `user:${userId}`;
  }

  buildRoleRoom(role: string): string {
    return `role:${role}`;
  }

  buildPermissionRoom(permission: string): string {
    return `permission:${permission}`;
  }

  buildClientTypeRoom(type: string): string {
    return `client-type:${type}`;
  }

  @SubscribeMessage('ping')
  handlePing(
    @ConnectedSocket() client: Socket,
    @MessageBody() payload?: Record<string, unknown>,
  ) {
    return {
      event: 'pong',
      clientId: client.id,
      received: payload ?? null,
      timestamp: new Date().toISOString(),
    };
  }

  private validateOrigin(client: Socket): void {
    const allowedOrigin = this.configService.getOrThrow<string>('security.panelWebOrigin');
    const origin = client.handshake.headers.origin;
    const clientType = client.handshake.auth?.clientType;
    const isDesktopClient =
      clientType == 'desktop' || typeof origin !== 'string' || origin.trim().length === 0;
    if (isDesktopClient) {
      return;
    }

    if (!isAllowedPanelOrigin(origin, allowedOrigin)) {
      throw new UnauthorizedException('Origen no autorizado para WebSocket.');
    }
  }
}