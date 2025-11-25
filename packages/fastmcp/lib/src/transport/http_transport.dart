// packages/fastmcp/lib/src/transport/http_transport.dart (Corrected for POST-first Handshake)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fastmcp/src/engine/mcp_engine.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'transport.dart';

enum HttpTransportMode { streamable }

class HttpTransportConfig {
  late final InternetAddress host;
  final int port;
  final HttpTransportMode mode;
  final String? authToken;
  final String endpoint;

  HttpTransportConfig({
    required this.port,
    InternetAddress? host,
    this.mode = HttpTransportMode.streamable,
    this.authToken,
    this.endpoint = '/mcp',
  }) {
    this.host = host ?? InternetAddress.anyIPv4;
  }
}

class HttpTransport implements ServerTransport {
  final HttpTransportConfig _config;
  final Logger _log = Logger('HttpTransport');
  final _messageController = StreamController<TransportMessage>.broadcast();
  final _closeCompleter = Completer<void>();
  HttpServer? _httpServer;

  McpEngine? _engine;

  final Map<dynamic, HttpResponse> _requestResponseStreams = {};
  final Map<String, StreamController<String>> _sessionNotificationStreams = {};
  final Map<String, dynamic> _sessionToActiveRequestId = {};

  HttpTransport(this._config);

  factory HttpTransport.streamable({
    required int port,
    InternetAddress? host,
    String? authToken,
    String endpoint = '/mcp',
  }) {
    return HttpTransport(
      HttpTransportConfig(
        port: port,
        host: host,
        authToken: authToken,
        endpoint: endpoint,
      ),
    );
  }

  void setEngine(McpEngine engine) {
    _engine = engine;
  }

  Future<void> start() async {
    try {
      _httpServer = await HttpServer.bind(_config.host, _config.port);
      _log.info(
        '🚀 HTTP servera listening on http://${_httpServer!.address.host}:${_httpServer!.port}${_config.endpoint}',
      );
      _httpServer!.listen(_handleRequest);
    } catch (e, s) {
      _log.severe('Failed to start HTTP server on port ${_config.port}', e, s);
      _closeCompleter.completeError(e);
      rethrow;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _setCorsHeaders(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    if (request.uri.path != _config.endpoint) {
      return _sendJsonError(request.response, HttpStatus.notFound, 'Not Found');
    }
    if (_config.authToken != null && !_validateAuth(request)) {
      return _sendJsonError(
        request.response,
        HttpStatus.unauthorized,
        'Unauthorized',
      );
    }
    try {
      switch (request.method) {
        case 'POST':
          await _handlePost(request);
          break;
        case 'GET':
          await _handleGet(request);
          break;
        case 'DELETE':
          await _handleDelete(request);
          break;
        default:
          _sendJsonError(
            request.response,
            HttpStatus.methodNotAllowed,
            'Method Not Allowed',
          );
      }
    } catch (e, s) {
      _log.warning(
        'Error in _handleRequest: ${request.method} ${request.uri.path}',
        e,
        s,
      );
      try {
        if (!request.response.headers.persistentConnection) {
          await request.response.close();
        }
      } catch (_) {}
    }
  }

  // REVERTED: This now REQUIRES a session ID, as it's for attaching the SSE stream to a pre-existing session.
  Future<void> _handleGet(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (_engine == null) {
      return _sendJsonError(
        request.response,
        HttpStatus.internalServerError,
        'Transport not connected to an engine.',
      );
    }
    if (sessionId == null ||
        _engine!.sessionManager.getSession(sessionId) == null) {
      _log.warning(
        'GET request received without a valid and active mcp-session-id header.',
      );
      return _sendJsonError(
        request.response,
        HttpStatus.badRequest,
        'A valid and active mcp-session-id header is required for GET requests.',
      );
    }

    _log.info(
      '✅ Attaching GET notification stream to existing session: $sessionId',
    );

    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Connection', 'keep-alive');
    request.response.headers.set('mcp-session-id', sessionId);

    _sessionNotificationStreams[sessionId]?.close();
    final controller = StreamController<String>();
    _sessionNotificationStreams[sessionId] = controller;

    request.response.done.whenComplete(() {
      _log.info(
        'GET notification stream for session $sessionId closed by client.',
      );
      _cleanupSession(sessionId);
      _engine!.sessionManager.endSession(sessionId);
    });

    controller.stream.listen(
      (data) {
        try {
          request.response.write(data);
        } catch (e) {
          _log.warning(
            'Failed to write to GET stream for session $sessionId, closing. Error: $e',
          );
          controller.close();
        }
      },
      onDone: () => request.response.close(),
      onError: (_) => request.response.close(),
      cancelOnError: true,
    );

    controller.add(': welcome to session $sessionId\n\n');
  }

  Future<void> _handlePost(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    if (body.isEmpty) {
      return _sendJsonError(
        request.response,
        HttpStatus.badRequest,
        'Empty request body.',
      );
    }
    try {
      final dynamic jsonData = jsonDecode(body);
      if (jsonData is Map<String, dynamic>) {
        _processSingleMessage(jsonData, request);
      } else {
        _sendJsonError(
          request.response,
          HttpStatus.badRequest,
          'Batch requests not supported.',
        );
      }
    } catch (e) {
      _sendJsonError(
        request.response,
        HttpStatus.badRequest,
        'Invalid JSON in request body.',
      );
    }
  }

  void _processSingleMessage(
    Map<String, dynamic> message,
    HttpRequest request,
  ) {
    final requestId = message['id'];
    var sessionId = request.headers.value('mcp-session-id');

    if (requestId != null) {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.headers.set('Cache-Control', 'no-cache');
      request.response.headers.set('Connection', 'keep-alive');
      _requestResponseStreams[requestId] = request.response;

      request.response.done.whenComplete(() {
        _requestResponseStreams.remove(requestId);
        if (sessionId != null &&
            _sessionToActiveRequestId[sessionId] == requestId) {
          _sessionToActiveRequestId.remove(sessionId);
        }
        _log.finer(
          'Cleaned up POST response stream for request ID: $requestId',
        );
      });
    }

    final isToolCall = (message['method'] == 'tools/call');
    if (sessionId != null && requestId != null && isToolCall) {
      _sessionToActiveRequestId[sessionId] = requestId;
    }

    _messageController.add(
      TransportMessage(
        data: message,
        transportId: requestId?.toString() ?? const Uuid().v4(),
        sessionId: sessionId,
      ),
    );
  }

  Future<void> _handleDelete(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId != null) {
      _cleanupSession(sessionId);
      _engine?.sessionManager.endSession(sessionId);
    }
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }

  @override
  void send(dynamic message, {String? sessionId}) {
    if (_closeCompleter.isCompleted) return;

    final isNotification = message is Map && message['id'] == null;
    final payload = 'data: ${jsonEncode(message)}\n\n';

    if (isNotification) {
      if (sessionId == null) {
        _log.warning(
          'Cannot send notification, session ID is missing.',
          message,
        );
        return;
      }
      final notificationStream = _sessionNotificationStreams[sessionId];
      if (notificationStream != null && !notificationStream.isClosed) {
        notificationStream.add(payload);
      } else {
        final activeRequestId = _sessionToActiveRequestId[sessionId];
        final fallbackStream = (activeRequestId != null)
            ? _requestResponseStreams[activeRequestId]
            : null;

        if (fallbackStream != null) {
          _log.finer(
            'No GET stream for session $sessionId. Sending notification via POST stream for request $activeRequestId.',
          );
          try {
            fallbackStream.write(payload);
          } catch (e) {
            _log.warning(
              'Failed to write notification to POST fallback stream for session $sessionId: $e',
            );
          }
        } else {
          _log.finer(
            'No active GET or POST stream for session $sessionId to send notification. Message dropped.',
          );
        }
      }
    } else {
      final requestId = message['id'];
      final responseStream = _requestResponseStreams.remove(requestId);

      if (responseStream != null) {
        try {
          if (sessionId != null) {
            responseStream.headers.set('mcp-session-id', sessionId);
          }
          responseStream.write(payload);
        } catch (e) {
          _log.warning(
            'Failed to write final response for request ID $requestId: $e',
          );
        } finally {
          try {
            responseStream.close();
          } catch (_) {}
          if (sessionId != null &&
              _sessionToActiveRequestId[sessionId] == requestId) {
            _sessionToActiveRequestId.remove(sessionId);
          }
        }
      } else {
        _log.warning(
          'No pending response stream found for request ID "$requestId" to send response.',
        );
      }
    }
  }

  @override
  void associateSession(String transportId, String sessionId) {
    // The engine now handles all session state. The transport is notified
    // so it knows which transportId maps to which sessionId.
    _log.info('Associating transport ID $transportId with session $sessionId.');
  }

  void _cleanupSession(String sessionId) {
    _log.info('Cleaning up transport resources for session: $sessionId');
    _sessionNotificationStreams.remove(sessionId)?.close();
    final activeRequestId = _sessionToActiveRequestId.remove(sessionId);
    if (activeRequestId != null) {
      _requestResponseStreams.remove(activeRequestId)?.close();
    }
  }

  bool _validateAuth(HttpRequest request) {
    final header = request.headers.value('Authorization');
    if (header == null) return false;
    final parts = header.split(' ');
    return parts.length == 2 &&
        parts[0] == 'Bearer' &&
        parts[1] == _config.authToken;
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Methods',
      'POST, GET, DELETE, OPTIONS',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, mcp-session-id',
    );
    response.headers.set('Access-Control-Expose-Headers', 'mcp-session-id');
  }

  void _sendJsonError(HttpResponse response, int code, String message) {
    _log.warning('Sending error to client: [$code] $message');
    try {
      if (response.connectionInfo != null) {
        if (response.headers.contentType == null) {
          response.headers.contentType = ContentType.json;
        }
        response.statusCode = code;
        response.write(
          jsonEncode({
            'error': {'code': code, 'message': message},
          }),
        );
        response.close();
      }
    } catch (e) {
      _log.severe('Failed to send JSON error response: $e');
    }
  }

  @override
  Stream<TransportMessage> get onMessage => _messageController.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  void close() {
    if (_closeCompleter.isCompleted) return;
    _log.info('Closing HTTP transport...');
    _httpServer?.close(force: true);
    _requestResponseStreams.values.forEach((s) {
      try {
        s.close();
      } catch (_) {}
    });
    _requestResponseStreams.clear();
    _sessionNotificationStreams.values.forEach((s) => s.close());
    _sessionNotificationStreams.clear();
    _sessionToActiveRequestId.clear();
    _messageController.close();
    _closeCompleter.complete();
  }
}
