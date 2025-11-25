import 'dart:async';

import 'package:fastmcp/src/models/session.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

class SessionManager {
  final Map<String, ClientSession> _sessions = {};
  final Map<String, String> _transportIdToSessionId = {};
  final _onConnectController = StreamController<ClientSession>.broadcast();
  final _onDisconnectController = StreamController<ClientSession>.broadcast();

  final Logger log = Logger('SessionManager');

  Stream<ClientSession> get onConnect => _onConnectController.stream;

  Stream<ClientSession> get onDisconnect => _onDisconnectController.stream;

  int getSessionCount() => _sessions.length;

  // REVERTED: This is the primary method for session creation.
  ClientSession createSession({
    required Map<String, dynamic> clientInfo,
    required String protocolVersion,
  }) {
    final sessionId = const Uuid().v4();
    final session = ClientSession(
      id: sessionId,
      connectedAt: DateTime.now(),
      clientInfo: clientInfo,
      protocolVersion: protocolVersion,
    );
    _sessions[sessionId] = session;
    _onConnectController.add(session);
    log.info('Ceated new session: $sessionId');
    return session;
  }

  void mapTransportId(String transportId, String sessionId) {
    _transportIdToSessionId[transportId] = sessionId;
  }

  void unmapTransportId(String transportId) {
    _transportIdToSessionId.remove(transportId);
  }

  void endSession(String sessionId) {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      _transportIdToSessionId.removeWhere((key, value) => value == sessionId);
      _onDisconnectController.add(session);
      log.info('Session ended: $sessionId');
    }
  }

  ClientSession? getSession(String? id) => id == null ? null : _sessions[id];

  ClientSession? getSessionFromTransportId(String? transportId) {
    if (transportId == null) return null;
    final sessionId = _transportIdToSessionId[transportId];
    return getSession(sessionId);
  }

  ClientSession? get firstSession =>
      _sessions.values.isNotEmpty ? _sessions.values.first : null;

  void dispose() {
    _onConnectController.close();
    _onDisconnectController.close();
  }
}
