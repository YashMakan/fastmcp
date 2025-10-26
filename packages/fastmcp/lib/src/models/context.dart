import 'package:meta/meta.dart';

import '../engine/mcp_engine.dart';
import '../models/session.dart';

/// A token that can be used to signal that an operation should be cancelled.
///
/// The engine will automatically create and manage this token for each tool call.
@immutable
class CancellationToken {
  final bool _isCancelled;

  /// Checks if a cancellation request has been received.
  ///
  /// In a long-running loop, you should check this property periodically
  /// and gracefully exit if it returns `true`.
  bool get isCancelled => _isCancelled;

  // This is an internal-only constructor. The developer never creates this.
  @internal
  const CancellationToken(this._isCancelled);
}

/// A context object injected into tool handlers for access to advanced features.
///
/// To use it, simply add it as a parameter to your tool function. The generator
/// will automatically provide it.
///
/// Example:
/// ```dart
/// @Tool()
/// Future<void> longTask(McpContext context, {int steps = 10}) async {
///   for (int i = 0; i < steps; i++) {
///     if (context.cancellationToken.isCancelled) return;
///     context.onProgress(i / steps);
///     await Future.delayed(Duration(seconds: 1));
///   }
/// }
/// ```
@immutable
class McpContext {
  /// The underlying server engine for very advanced, direct operations.
  /// Use with caution.
  final McpEngine engine;

  /// The session of the client that made the request.
  final ClientSession session;

  /// The unique ID of the current tool call operation.
  final String operationId;

  /// A token to check if this operation has been cancelled.
  final CancellationToken cancellationToken;

  /// A callback to report progress for this operation.
  ///
  /// [progress] is a value between 0.0 and 1.0.
  /// [message] is an optional string describing the current step.
  void onProgress(double progress, [String? message]) {
    engine.operationManager.notifyProgress(
      operationId: operationId,
      progress: progress,
      message: message,
    );
  }

  @internal
  const McpContext({
    required this.engine,
    required this.session,
    required this.operationId,
    required this.cancellationToken,
  });

  McpContext copyWith({
    McpEngine? engine,
    ClientSession? session,
    String? operationId,
    CancellationToken? cancellationToken,
  }) {
    return McpContext(
      engine: engine ?? this.engine,
      session: session ?? this.session,
      operationId: operationId ?? this.operationId,
      cancellationToken: cancellationToken ?? this.cancellationToken,
    );
  }
}
