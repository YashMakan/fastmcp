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

  /// Static API Key / Token
  final String? authToken;

  /// Dynamic validator (for OAuth/JWT)
  final AuthValidator? authValidator;

  final String endpoint;

  final String? resourceMetadataUrl;

  final Map<String, HttpRequestCallback>? extraHandlers;

  HttpTransportConfig({
    required this.port,
    InternetAddress? host,
    this.mode = HttpTransportMode.streamable,
    this.authToken,
    this.authValidator, // Add this
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

  // Map Session ID -> SSE Stream Controller
  final Map<String, StreamController<String>> _sseControllers = {};

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

    if (_config.extraHandlers != null &&
        _config.extraHandlers!.containsKey(request.uri.path)) {
      await _config.extraHandlers![request.uri.path]!(request);
      return;
    }

    // Basic path validation
    if (!request.uri.path.startsWith(_config.endpoint)) {
      return _sendJsonError(request.response, HttpStatus.notFound, 'Not Found');
    }

    final requiresAuth =
        _config.authToken != null || _config.authValidator != null;

    if (requiresAuth) {
      final isValid = await _validateAuth(request);
      if (!isValid) {
        // REQUIRED BY CHATGPT: Return WWW-Authenticate header with metadata URL
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
    }

    try {
      switch (request.method) {
        case 'GET':
          // 1. Handle the SSE Connection Request
          await _handleSseConnection(request);
          break;
        case 'POST':
          // 2. Handle Incoming Messages
          await _handlePost(request);
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
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleSseConnection(HttpRequest request) async {
    final sessionId = const Uuid().v4();
    _log.info('New SSE connection established. ID: $sessionId');

    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Connection', 'keep-alive');
    // Important for SSE to flush immediately
    request.response.bufferOutput = false;

    final controller = StreamController<String>();
    _sseControllers[sessionId] = controller;

    // Monitor for client disconnect to cleanup
    request.response.done.then((_) {
      if (_sseControllers.containsKey(sessionId)) {
        _log.info('Client disconnected SSE stream: $sessionId');
        _sseControllers.remove(sessionId);
        _engine?.sessionManager.endSession(sessionId);
        if (!controller.isClosed) controller.close();
      }
    }, onError: (_) {});

    // Queue the endpoint event
    final postEndpoint = '${_config.endpoint}?sessionId=$sessionId';
    _sendSseEvent(controller, 'endpoint', postEndpoint);
    _log.info('Sent endpoint event: $postEndpoint');

    try {
      // Pipe controller -> response
      await request.response.addStream(
        controller.stream.map((s) => utf8.encode(s)),
      );
    } catch (_) {
      // Ignore errors (client disconnected)
    } finally {
      // Ensure response is closed
      await request.response.close();
      // Double check cleanup
      _sseControllers.remove(sessionId);
    }
  }

  Future<void> _handlePost(HttpRequest request) async {
    // 1. Extract Session ID from Query Parameter
    final sessionId = request.uri.queryParameters['sessionId'];

    if (sessionId == null || !_sseControllers.containsKey(sessionId)) {
      return _sendJsonError(
        request.response,
        HttpStatus.unauthorized,
        'Session not found or expired. Connect via SSE first.',
      );
    }

    // 2. Read Body
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

      // 3. Send 202 Accepted immediately
      // MCP specifies that POST requests are for transport only.
      // The actual response goes back over the SSE stream.
      request.response.statusCode = HttpStatus.accepted;
      request.response.write('Accepted');
      await request.response.close();

      // 4. Pass message to Engine
      if (jsonData is Map<String, dynamic>) {
        _messageController.add(
          TransportMessage(
            data: jsonData,
            transportId: sessionId, // Use session ID as transport ID
            sessionId: sessionId,
          ),
        );
      }
    } catch (e) {
      // If we haven't closed the response yet
      try {
        _sendJsonError(request.response, HttpStatus.badRequest, 'Invalid JSON');
      } catch (_) {}
    }
  }

  // Send data OUT via the SSE stream
  @override
  void send(dynamic message, {String? sessionId}) {
    if (sessionId == null) {
      _log.warning('Cannot send message without sessionId');
      return;
    }

    final controller = _sseControllers[sessionId];
    if (controller == null || controller.isClosed) {
      _log.warning('SSE stream for session $sessionId is closed or missing');
      return;
    }

    // Wrap JSON-RPC message in an SSE "message" event
    _sendSseEvent(controller, 'message', jsonEncode(message));
  }

  void _sendSseEvent(
    StreamController<String> controller,
    String event,
    String data,
  ) {
    if (controller.isClosed) return;
    controller.add('event: $event\n');
    controller.add('data: $data\n\n');
  }

  @override
  void associateSession(String transportId, String sessionId) {
    // In this implementation, transportId IS the sessionId, so this is a no-op
  }

  Future<bool> _validateAuth(HttpRequest request) async {
    // 1. Extract the token
    final header = request.headers.value('Authorization');
    if (header == null) return false;

    final parts = header.split(' ');
    if (parts.length != 2 || parts[0] != 'Bearer') return false;

    final token = parts[1];

    // 2. Check Static Token (API Key style)
    if (_config.authToken != null && token == _config.authToken) {
      return true;
    }

    // 3. Check Custom Validator (OAuth/JWT style)
    if (_config.authValidator != null) {
      try {
        // Await specifically handles both Future<bool> and bool
        return await _config.authValidator!(token);
      } catch (e) {
        _log.warning('Error executing authValidator: $e');
        return false;
      }
    }

    // 4. If neither matched/existed, auth failed
    return false;
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization',
    );
  }

  void _sendJsonError(HttpResponse response, int code, String message) {
    try {
      response.statusCode = code;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': message}));
      response.close();
    } catch (_) {}
  }

  @override
  Stream<TransportMessage> get onMessage => _messageController.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  void close() {
    _httpServer?.close(force: true);
    _sseControllers.values.forEach((c) => c.close());
    _sseControllers.clear();
    _messageController.close();
    if (!_closeCompleter.isCompleted) _closeCompleter.complete();
  }
}
