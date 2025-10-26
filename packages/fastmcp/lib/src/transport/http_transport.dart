import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  final Map<dynamic, HttpResponse> _requestResponseStreams = {};
  final Map<String, StreamController<String>> _sessionNotificationStreams = {};
  final Map<String, dynamic> _sessionToActiveRequestId = {};
  final Set<String> _activeSessions = {};

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
      return request.response.close();
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
    }
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

    if (sessionId != null && !_activeSessions.contains(sessionId)) {
      if (message['method'] != 'initialize') {
        _log.warning('Request with unknown session ID "$sessionId" received.');
        sessionId = null;
      }
    }

    _messageController.add(
      TransportMessage(
        data: message,
        transportId: requestId?.toString() ?? const Uuid().v4(),
        sessionId: sessionId,
      ),
    );
  }

  Future<void> _handleGet(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId == null || !_activeSessions.contains(sessionId)) {
      return _sendJsonError(
        request.response,
        HttpStatus.badRequest,
        'A valid and active mcp-session-id header is required.',
      );
    }

    _log.info('✅ Establishing GET notification stream for session: $sessionId');

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
      _sessionNotificationStreams.remove(sessionId)?.close();
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
    );

    controller.add(': welcome to session $sessionId\n\n');
  }

  Future<void> _handleDelete(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId != null) _cleanupSession(sessionId);
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
        return _log.warning(
          'Cannot send notification, session ID is missing.',
          message,
        );
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
          responseStream.close();
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
    if (!_activeSessions.contains(sessionId)) {
      _activeSessions.add(sessionId);
      _log.info('New session activated: $sessionId.');
    }
  }

  void _cleanupSession(String sessionId) {
    _log.info('Cleaning up session: $sessionId');
    _activeSessions.remove(sessionId);
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
  }

  void _sendJsonError(HttpResponse response, int code, String message) {
    response.statusCode = code;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'error': message}));
    response.close();
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
    for (var s in _requestResponseStreams.values) {
      s.close();
    }
    for (var s in _sessionNotificationStreams.values) {
      s.close();
    }
    _requestResponseStreams.clear();
    _sessionNotificationStreams.clear();
    _activeSessions.clear();
    _sessionToActiveRequestId.clear();
    _messageController.close();
    _closeCompleter.complete();
  }
}
