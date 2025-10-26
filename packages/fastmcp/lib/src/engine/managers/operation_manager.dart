import 'package:collection/collection.dart';
import 'package:fastmcp/src/engine/mcp_engine.dart';
import 'package:fastmcp/src/protocol/protocol.dart';
import 'package:uuid/uuid.dart';

/// Represents a pending, long-running operation.
class PendingOperation {
  final String id;
  final String sessionId;
  final String type;
  final DateTime createdAt;
  bool isCancelled = false;
  final dynamic originalRequestId;
  final dynamic progressToken;

  PendingOperation({
    required this.id,
    required this.sessionId,
    required this.type,
    this.progressToken,
    this.originalRequestId,
  }) : createdAt = DateTime.now();
}

class OperationManager {
  final Map<String, PendingOperation> _operations = {};
  late final McpEngine _engine;

  void setEngine(McpEngine engine) {
    _engine = engine;
  }

  /// Registers a new operation and returns its unique ID.
  String register({
    required String sessionId,
    required String type,
    dynamic progressToken,
    dynamic originalRequestId,
  }) {
    final operationId = const Uuid().v4();
    _operations[operationId] = PendingOperation(
      id: operationId,
      sessionId: sessionId,
      type: type,
      progressToken: progressToken,
      originalRequestId: originalRequestId,
    );
    return operationId;
  }

  PendingOperation? getOperationFromToken(dynamic token) {
    return _operations.values.firstWhereOrNull(
      (op) => op.progressToken == token,
    );
  }

  /// Marks an operation as cancelled.
  void cancel(String operationId) {
    final operation = _operations[operationId];
    if (operation != null) {
      operation.isCancelled = true;
    }
  }

  /// Checks if an operation has been cancelled.
  bool isCancelled(String operationId) {
    return _operations[operationId]?.isCancelled ??
        true; // Default to cancelled if not found
  }

  /// Unregisters an operation when it completes or fails.
  void unregister(String operationId) {
    _operations.remove(operationId);
  }

  /// Sends a progress notification to the client *if* a progressToken exists.
  void notifyProgress({
    required String operationId,
    required double progress,
    String? message,
  }) {
    final operation = _operations[operationId];
    print("operation::${operation?.progressToken}");
    if (operation == null || operation.progressToken == null) {
      return;
    }

    _engine.sendNotification(
      sessionId: operation.sessionId,
      method: McpProtocol.progress,
      params: {
        'progressToken': operation.progressToken,
        'progress': progress,
        'total': 1.0,
        if (message != null) 'message': message,
      },
    );
  }

  void cleanupSession(String sessionId) {
    _operations.removeWhere((key, op) => op.sessionId == sessionId);
  }
}
