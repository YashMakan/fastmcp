import 'dart:async';
import 'dart:io';

/// A wrapper for messages received from a transport, including an ID
/// that the transport uses to identify the connection/client.
class TransportMessage {
  /// The raw message data (typically a Map<String, dynamic>).
  final dynamic data;

  /// An ID unique to the transport's connection
  final String transportId;

  /// The official `fastmcp` session ID, if it has been established.
  String? sessionId;

  /// For HTTP transports, this holds the raw response object.
  final HttpResponse? httpResponse;

  TransportMessage({
    required this.data,
    required this.transportId,
    this.sessionId,
    this.httpResponse,
  });
}

/// Abstract base class for server transport implementations.
abstract class ServerTransport {
  /// A stream of incoming messages wrapped with transport-level metadata.
  Stream<TransportMessage> get onMessage;

  Future<void> get onClose;

  /// Sends a message, optionally targeting a specific session.
  void send(dynamic message, {String? sessionId});

  /// Associates a transport-level connection ID with a fastmcp session ID.
  void associateSession(String transportId, String sessionId);

  void close();
}
