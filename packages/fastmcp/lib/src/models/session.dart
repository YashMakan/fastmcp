import 'package:meta/meta.dart';

/// Represents a connected client's session.
@immutable
class ClientSession {
  final String id;
  final DateTime connectedAt;
  final Map<String, dynamic> clientInfo;
  final String protocolVersion;

  const ClientSession({
    required this.id,
    required this.connectedAt,
    required this.clientInfo,
    required this.protocolVersion,
  });

  factory ClientSession.placeholder() {
    return ClientSession(
      id: 'placeholder',
      connectedAt: DateTime.now(),
      clientInfo: {},
      protocolVersion: '',
    );
  }
}
