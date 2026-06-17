enum SyncConnectionStatus {
  disconnected,
  connecting,
  connected,
  error;

  bool get isConnected => this == SyncConnectionStatus.connected;
  bool get isBusy => this == SyncConnectionStatus.connecting;
}