// FILE: ./src/transport/http_transport.dart (REVISED AND CORRECTED)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fastmcp/src/engine/mcp_engine.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'transport.dart';

enum HttpTransportMode { streamable }

typedef AuthValidator = FutureOr<bool> Function(String token);
typedef HttpRequestCallback = FutureOr<void> Function(HttpRequest request);

class HttpTransportConfig {
  late final InternetAddress host;
  final int port;
  final HttpTransportMode mode;
  final String? authToken;
  final AuthValidator? authValidator;
  final String endpoint;
  final String? resourceMetadataUrl;
  final Map<String, HttpRequestCallback>? extraHandlers;

  HttpTransportConfig({
    required this.port,
    InternetAddress? host,
    this.mode = HttpTransportMode.streamable,
    this.authToken,
    this.authValidator,
    this.endpoint = '/mcp',
    this.resourceMetadataUrl,
    this.extraHandlers,
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

  final Map<dynamic, HttpResponse> _pendingHttpResponses = {};
  final Map<String, StreamController<String>> _sseNotificationControllers = {};

  HttpTransport(this._config);

  factory HttpTransport.streamable({
    required int port,
    InternetAddress? host,
    String? authToken,
    AuthValidator? authValidator,
    String endpoint = '/mcp',
    String? resourceMetadataUrl,
    Map<String, HttpRequestCallback>? extraHandlers,
  }) {
    return HttpTransport(
      HttpTransportConfig(
        port: port,
        host: host,
        authToken: authToken,
        authValidator: authValidator,
        endpoint: endpoint,
        resourceMetadataUrl: resourceMetadataUrl,
        extraHandlers: extraHandlers,
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
        '🚀 HTTP server listening on http://${_httpServer!.address.host}:${_httpServer!.port}${_config.endpoint}',
      );
      _httpServer!.listen(_handleRequest);
    } catch (e, s) {
      _log.severe('Failed to start HTTP server on port ${_config.port}', e, s);
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

    if (_config.extraHandlers?.containsKey(request.uri.path) ?? false) {
      await _config.extraHandlers![request.uri.path]!(request);
      return;
    }

    if (!request.uri.path.startsWith(_config.endpoint)) {
      return _sendJsonError(request.response, HttpStatus.notFound, 'Not Found');
    }

    if ((_config.authToken != null || _config.authValidator != null) &&
        !(await _validateAuth(request))) {
      if (_config.resourceMetadataUrl != null) {
        request.response.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer resource_metadata="${_config.resourceMetadataUrl}", error="invalid_token"',
        );
      }
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
          await _handleGetNotifications(request);
          break;
        case 'DELETE':
          await _handleDeleteSession(request);
          break;
        default:
          _sendJsonError(
            request.response,
            HttpStatus.methodNotAllowed,
            'Method Not Allowed',
          );
      }
    } catch (e, s) {
      _log.warning('Error handling request', e, s);
      // The try-catch here is sufficient, no need for an extra check.
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePost(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    if (body.isEmpty) {
      return _sendJsonError(
        request.response,
        HttpStatus.badRequest,
        'Empty body',
      );
    }

    try {
      final dynamic jsonData = jsonDecode(body);
      if (jsonData is! Map<String, dynamic>) {
        return _sendJsonError(
          request.response,
          HttpStatus.badRequest,
          'Invalid JSON format',
        );
      }

      final requestId = jsonData['id'];
      final sessionId = request.headers.value('mcp-session-id');

      if (requestId != null) {
        _pendingHttpResponses[requestId] = request.response;
        request.response.done.whenComplete(() {
          _pendingHttpResponses.remove(requestId);
        });
      } else {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
      }

      _messageController.add(
        TransportMessage(
          data: jsonData,
          transportId: const Uuid().v4(),
          sessionId: sessionId,
          httpResponse: request.response,
        ),
      );
    } catch (e) {
      _sendJsonError(request.response, HttpStatus.badRequest, 'Invalid JSON');
    }
  }

  Future<void> _handleGetNotifications(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');

    if (sessionId == null ||
        _engine?.sessionManager.getSession(sessionId) == null) {
      return _sendJsonError(
        request.response,
        HttpStatus.unauthorized,
        'Session not found or expired. Initialize a session via POST first.',
      );
    }
    _log.info('Client opening notification stream for session: $sessionId');

    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Connection', 'keep-alive');
    request.response.bufferOutput = false;

    _sseNotificationControllers[sessionId]?.close();
    final controller = StreamController<String>();
    _sseNotificationControllers[sessionId] = controller;

    request.response.done.then((_) {
      _log.info('Client disconnected notification stream: $sessionId');
      _sseNotificationControllers.remove(sessionId)?.close();
    });

    try {
      await request.response.addStream(controller.stream.map(utf8.encode));
    } finally {
      await request.response.close();
      _sseNotificationControllers.remove(sessionId)?.close();
    }
  }

  Future<void> _handleDeleteSession(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId != null) {
      _log.info('Client requested termination of session: $sessionId');
      _engine?.sessionManager.endSession(sessionId);
    }
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }

  @override
  void send(dynamic message, {String? sessionId}) {
    if (message == null || message is! Map) {
      _log.finer("Ignoring null or non-map message for send.");
      return;
    }

    final requestId = message['id'];
    final isNotification = requestId == null;

    if (!isNotification && _pendingHttpResponses.containsKey(requestId)) {
      final response = _pendingHttpResponses.remove(requestId)!;
      // FIX: The incorrect `if (response.done.isCompleted)` check is removed.
      // We now rely on the try/catch block for robustness.
      try {
        response.headers.contentType = ContentType.json;
        if (message['result']?['serverInfo'] != null && sessionId != null) {
          response.headers.set('mcp-session-id', sessionId);
        }
        response.write(jsonEncode(message));
        response.close();
        _log.info('Sent synchronous response for request ID: $requestId');
      } catch (e, s) {
        _log.severe(
          'Failed to send synchronous response for $requestId. The client may have disconnected.',
          e,
          s,
        );
      }
    } else if (isNotification && sessionId != null) {
      final controller = _sseNotificationControllers[sessionId];
      if (controller != null && !controller.isClosed) {
        final data = jsonEncode(message);
        controller.add('data: $data\n\n');
        _log.info('Sent notification to session $sessionId via SSE stream.');
      } else {
        _log.warning(
          'No active notification stream for session $sessionId. Notification dropped.',
        );
      }
    } else {
      _log.warning(
        'Could not send message: No pending response for ID "$requestId" and not a valid notification.',
      );
    }
  }

  @override
  void associateSession(String transportId, String sessionId) {
    _log.finer('Session $sessionId associated with transportId $transportId');
  }

  Future<bool> _validateAuth(HttpRequest request) async {
    final header = request.headers.value('Authorization');
    if (header == null) return false;
    final parts = header.split(' ');
    if (parts.length != 2 || parts[0].toLowerCase() != 'bearer') return false;
    final token = parts[1];

    if (_config.authToken != null) return token == _config.authToken;
    if (_config.authValidator != null) {
      try {
        return await _config.authValidator!(token);
      } catch (e) {
        _log.warning('Error in authValidator: $e');
        return false;
      }
    }
    return false;
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Methods',
      'POST, GET, DELETE, OPTIONS',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, Mcp-Session-Id',
    );
    response.headers.set('Access-Control-Expose-Headers', 'Mcp-Session-Id');
  }

  void _sendJsonError(HttpResponse response, int code, String message) {
    // FIX: Removed the incorrect `if (response.done.isCompleted)` check.
    // The surrounding try/catch in the calling methods is sufficient.
    try {
      response.statusCode = code;
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'error': {'code': code, 'message': message},
        }),
      );
      response.close();
    } catch (_) {
      // Ignore errors here, as it means the client has already disconnected.
    }
  }

  @override
  Stream<TransportMessage> get onMessage => _messageController.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  void close() {
    _httpServer?.close(force: true);
    _pendingHttpResponses.values.forEach((r) => r.detachSocket());
    _pendingHttpResponses.clear();
    _sseNotificationControllers.values.forEach((c) => c.close());
    _sseNotificationControllers.clear();
    _messageController.close();
    if (!_closeCompleter.isCompleted) _closeCompleter.complete();
  }
}
