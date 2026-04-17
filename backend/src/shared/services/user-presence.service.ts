import { Injectable } from '@nestjs/common';

type PresenceClientType = 'desktop' | 'panel';

type PresenceConnection = {
  socketId: string;
  clientType: PresenceClientType;
  connectedAt: string;
};

@Injectable()
export class UserPresenceService {
  private readonly connectionsByUser = new Map<string, Map<string, PresenceConnection>>();
  private readonly socketToUser = new Map<string, string>();

  markConnected(userId: string, clientType: PresenceClientType, socketId: string): void {
    const nextConnection: PresenceConnection = {
      socketId,
      clientType,
      connectedAt: new Date().toISOString(),
    };

    const userConnections = this.connectionsByUser.get(userId) ?? new Map<string, PresenceConnection>();
    userConnections.set(socketId, nextConnection);
    this.connectionsByUser.set(userId, userConnections);
    this.socketToUser.set(socketId, userId);
  }

  markDisconnected(socketId: string): void {
    const userId = this.socketToUser.get(socketId);
    if (!userId) {
      return;
    }

    const userConnections = this.connectionsByUser.get(userId);
    userConnections?.delete(socketId);
    if (userConnections != null && userConnections.size === 0) {
      this.connectionsByUser.delete(userId);
    }
    this.socketToUser.delete(socketId);
  }

  getPresenceForUser(userId: string) {
    const userConnections = this.connectionsByUser.get(userId);
    const connections = [...(userConnections?.values() ?? [])].sort((left, right) =>
      left.connectedAt.localeCompare(right.connectedAt),
    );

    return {
      isOnline: connections.length > 0,
      connectionCount: connections.length,
      clientTypes: [...new Set(connections.map((connection) => connection.clientType))],
      connectedAt: connections.length > 0 ? connections[0].connectedAt : null,
    };
  }
}