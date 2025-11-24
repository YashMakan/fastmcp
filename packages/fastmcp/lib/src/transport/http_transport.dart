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

  // Maps a request ID to its temporary response stream for POST requests.
  final Map<dynamic, HttpResponse> _requestResponseStreams = {};
  // Maps a session ID to its long-lived SSE stream for GET requests.
  final Map<String, StreamController<String>> _sessionNotificationStreams = {};
  // Maps a session ID to the ID of its currently active tool call request.
  final Map<String, dynamic> _sessionToActiveRequestId = {};
  // Holds all currently active session IDs.
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
      if (!request.response.headers.persistentConnection) {
        await request.response.close();
      }
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

    // For POST requests that expect a response, we hold onto the response stream.
    if (requestId != null) {
      // Set SSE headers for the response stream even on POST, as notifications
      // can be sent as a fallback on this stream if the GET stream is not available.
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.headers.set('Cache-Control', 'no-cache');
      request.response.headers.set('Connection', 'keep-alive');
      _requestResponseStreams[requestId] = request.response;

      // Cleanup when the POST connection eventually closes.
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

    // Track the active tool call for a session to use as a notification fallback.
    final isToolCall = (message['method'] == 'tools/call');
    if (sessionId != null && requestId != null && isToolCall) {
      _sessionToActiveRequestId[sessionId] = requestId;
    }

    // The first message from a client on a new session MUST be 'initialize'.
    // Here we trust the session ID provided in the header because the client
    // could only have learned it from a previous successful GET request.
    if (sessionId != null &&
        !_activeSessions.contains(sessionId) &&
        message['method'] != 'initialize') {
      _log.warning(
        'Request with unknown or inactive session ID "$sessionId" received for method "${message['method']}". Ignoring session.',
      );
      sessionId =
          null; // Treat as an invalid request for routing purposes in the engine.
    }

    _messageController.add(
      TransportMessage(
        data: message,
        transportId: requestId?.toString() ?? const Uuid().v4(),
        sessionId: sessionId,
      ),
    );
  }

  // =========== MAJOR CHANGE AREA START ===========
  Future<void> _handleGet(HttpRequest request) async {
    // A GET request establishes a new session and a long-lived SSE stream.
    // It does not require a session ID header.

    final sessionId = const Uuid().v4();
    _activeSessions.add(sessionId);

    _log.info(
      '✅ New client connected. Establishing SSE stream for session: $sessionId',
    );

    // Set SSE headers to keep the connection open.
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Connection', 'keep-alive');

    // CRITICAL: Send the new session ID back to the client in a header.
    request.response.headers.set('mcp-session-id', sessionId);

    // Clean up any old stream controller for this ID just in case of a rapid reconnect.
    _sessionNotificationStreams[sessionId]?.close();

    final controller = StreamController<String>();
    _sessionNotificationStreams[sessionId] = controller;

    // When the client closes the connection, clean up server-side resources.
    request.response.done.whenComplete(() {
      _log.info(
        'GET notification stream for session $sessionId closed by client.',
      );
      _cleanupSession(sessionId);
    });

    // Pipe the controller's events to the HTTP response.
    controller.stream.listen(
      (data) {
        try {
          request.response.write(data);
        } catch (e) {
          _log.warning(
            'Failed to write to GET stream for session $sessionId, closing. Error: $e',
          );
          controller.close(); // This will trigger onDone below.
        }
      },
      onDone: () => request.response.close(),
      onError: (_) => request.response.close(),
    );

    // Send an initial comment to confirm the connection is open.
    controller.add(': welcome to session $sessionId\n\n');
  }
  // =========== MAJOR CHANGE AREA END ===========

  Future<void> _handleDelete(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId != null) {
      _cleanupSession(sessionId);
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
        // Fallback for clients that might not support the GET stream correctly.
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
      // This is a final response to a POST request.
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
          // The main request is done, so it's no longer the active fallback.
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
    // This method is called by the engine after a successful 'initialize'
    // It confirms that a pre-initialized session is now fully active.
    if (!_activeSessions.contains(sessionId)) {
      _activeSessions.add(sessionId);
      _log.info('Session $sessionId has been formally initialized.');
    }
    // No need to log "New session activated" here anymore, as it's
    // more accurately logged when the GET request first arrives.
  }

  void _cleanupSession(String sessionId) {
    _log.info('Cleaning up resources for session: $sessionId');
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
    // NEW & CRITICAL: Expose the custom header so the client's browser can read it.
    response.headers.set('Access-Control-Expose-Headers', 'mcp-session-id');
  }

  void _sendJsonError(HttpResponse response, int code, String message) {
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
    _requestResponseStreams.clear();
    for (var s in _sessionNotificationStreams.values) {
      s.close();
    }
    _sessionNotificationStreams.clear();
    _activeSessions.clear();
    _sessionToActiveRequestId.clear();
    _messageController.close();
    _closeCompleter.complete();
  }
}
