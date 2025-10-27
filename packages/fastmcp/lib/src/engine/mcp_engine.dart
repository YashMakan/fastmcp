import 'dart:async';
import 'dart:io';

import 'package:fastmcp/src/components/capabilities.dart';
import 'package:fastmcp/src/models/context.dart';
import 'package:fastmcp/src/models/session.dart';
import 'package:fastmcp/src/protocol/error.dart';
import 'package:fastmcp/src/protocol/protocol.dart';
import 'package:fastmcp/src/transport/transport.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'managers/operation_manager.dart';
import 'managers/prompt_manager.dart';
import 'managers/resource_manager.dart';
import 'managers/session_manager.dart';
import 'managers/tool_manager.dart';

typedef MethodHandler =
    Future<void> Function({
      required TransportMessage event,
      required ClientSession session,
      required Map<String, dynamic> params,
      required dynamic id,
    });

class McpEngine {
  final String name;
  final String version;
  final ServerCapabilities capabilities;
  final Logger log = Logger('McpEngine');

  final SessionManager sessionManager = SessionManager();
  final ToolManager toolManager = ToolManager();
  final ResourceManager resourceManager = ResourceManager();
  final PromptManager promptManager = PromptManager();
  final OperationManager operationManager = OperationManager();

  ServerTransport? _transport;
  StreamSubscription<TransportMessage>? _transportSubscription;

  late final Map<String, MethodHandler> _methodRouter;

  final Map<dynamic, HttpResponse> _httpResponseMap = {};

  McpEngine({
    required this.name,
    required this.version,
    required this.capabilities,
  }) {
    _methodRouter = {
      McpProtocol.initialize: _handleInitialize,
      McpProtocol.ping: _handlePing,
      McpProtocol.listTools: _handleListTools,
      McpProtocol.callTool: _handleCallTool,
      McpProtocol.listResources: _handleListResources,
      McpProtocol.readResource: _handleReadResource,
      McpProtocol.listPrompts: _handleListPrompts,
      McpProtocol.getPrompt: _handleGetPrompt,
      McpProtocol.cancel: _handleCancel,
    };
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((rec) {
      print(
        '[${rec.level.name}] ${rec.time.toIso8601String().substring(11, 23)} [${rec.loggerName}]: ${rec.message}',
      );
    });

    operationManager.setEngine(this);
    sessionManager.onDisconnect.listen((session) {
      log.info('Session ${session.id} disconnected. Cleaning up operations.');
      operationManager.cleanupSession(session.id);
    });
  }

  void connect(ServerTransport transport) {
    if (_transport != null) throw StateError('Engine is already connected.');
    _transport = transport;
    _transportSubscription = transport.onMessage.listen(_dispatchMessage);
    log.info('Engine connected to transport.');
  }

  Future<void> _dispatchMessage(TransportMessage event) async {
    final message = event.data;
    if (message is! Map<String, dynamic>) {
      _sendError(
        id: null,
        error: const McpError(
          code: McpError.parseError,
          message: "Invalid message format",
        ),
        sessionId: event.sessionId,
      );
      return;
    }

    final id = message['id'];

    if (id != null && event.httpResponse != null) {
      _httpResponseMap[id] = event.httpResponse!;
    }

    final method = message['method'] as String?;

    if (method == null) {
      _sendError(
        id: id,
        error: const McpError(
          code: McpError.invalidRequest,
          message: "Method is missing",
        ),
        sessionId: event.sessionId,
      );
      return;
    }

    final responseStream = message.remove('_http_response') as HttpResponse?;
    if (id != null && responseStream != null) {
      _httpResponseMap[id] = responseStream;
    }

    ClientSession? session;
    if (method == McpProtocol.initialize) {
      session = ClientSession.placeholder();
    } else {
      session = sessionManager.getSession(event.sessionId);
      if (session == null) {
        _sendError(
          id: id,
          error: const McpError(
            code: McpError.invalidRequest,
            message: "Session not initialized or has expired.",
          ),
          sessionId: event.sessionId,
        );
        return;
      }
    }

    final handler = _methodRouter[method];
    if (handler == null) {
      _sendError(
        id: id,
        error: McpError(
          code: McpError.methodNotFound,
          message: "Method '$method' not found",
        ),
        sessionId: event.sessionId,
      );
      return;
    }

    try {
      await handler(
        event: event,
        session: session,
        params: message['params'] as Map<String, dynamic>? ?? {},
        id: id,
      );
    } catch (e, s) {
      log.severe('Unhandled error in handler for method "$method"', e, s);
      _sendError(
        id: id,
        error: McpError(
          code: McpError.internalError,
          message: 'Internal Server Error: $e',
        ),
        sessionId: event.sessionId,
      );
    }
  }

  Future<void> _handleInitialize({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    final newSession = sessionManager.createSession(
      clientInfo: params['clientInfo'] ?? {},
      protocolVersion: params['protocolVersion'] ?? McpProtocol.v2025_03_26,
    );
    _transport?.associateSession(event.transportId, newSession.id);
    _sendResult(id, {
      'protocolVersion': newSession.protocolVersion,
      'serverInfo': {'name': name, 'version': version},
      'capabilities': capabilities.toJson(),
    }, newSession.id);
  }

  /// Handles a ping request by immediately sending back an empty result.
  /// This is used to verify connection health.
  Future<void> _handlePing({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    _sendResult(id, {}, session.id);
  }

  Future<void> _handleListTools({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    final tools = toolManager.listTools();
    _sendResult(id, {
      'tools': tools.map((t) => t.toJson()).toList(),
    }, session.id);
  }

  Future<void> _handleCallTool({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    final toolName = params['name'] as String?;
    if (toolName == null) {
      return _sendError(
        id: id,
        error: const McpError(
          code: McpError.invalidParams,
          message: "Missing required parameter: 'name'",
        ),
        sessionId: session.id,
      );
    }
    final handler = toolManager.getHandler(toolName);
    if (handler == null) {
      return _sendError(
        id: id,
        error: McpError(
          code: McpError.toolNotFound,
          message: "Tool '$toolName' not found",
        ),
        sessionId: session.id,
      );
    }

    final meta = params['_meta'] as Map<String, dynamic>?;
    final progressToken = meta?['progressToken'];
    final arguments = params['arguments'] ?? {};

    final operationId = operationManager.register(
      sessionId: session.id,
      type: toolName,
      progressToken: progressToken,
      originalRequestId: id,
    );

    final context = McpContext(
      engine: this,
      session: session,
      operationId: operationId,
      cancellationToken: CancellationToken(
        operationManager.isCancelled(operationId),
      ),
    );

    handler(arguments, context)
        .then((result) => _sendResult(id, result.toJson(), session.id))
        .catchError((e, s) {
          log.severe('Error during tool execution for "$toolName"', e, s);
          _sendError(
            id: id,
            error: McpError(
              code: McpError.internalError,
              message: 'Tool execution failed: $e',
            ),
            sessionId: session.id,
          );
        })
        .whenComplete(() => operationManager.unregister(operationId));
  }

  Future<void> _handleListResources({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    final resources = resourceManager.listResources();
    _sendResult(id, {
      'resources': resources.map((r) => r.toJson()).toList(),
    }, session.id);
  }

  Future<void> _handleReadResource({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    final uri = params['uri'] as String?;
    if (uri == null) {
      return _sendError(
        id: id,
        error: const McpError(
          code: McpError.invalidParams,
          message: "Missing required parameter: 'uri'",
        ),
        sessionId: session.id,
      );
    }
    final handler = resourceManager.getHandler(uri);
    if (handler == null) {
      return _sendError(
        id: id,
        error: McpError(
          code: McpError.resourceNotFound,
          message: "Resource '$uri' not found",
        ),
        sessionId: session.id,
      );
    }
    final context = McpContext(
      engine: this,
      session: session,
      operationId: id?.toString() ?? const Uuid().v4(),
      cancellationToken: const CancellationToken(false),
    );
    final result = await handler(uri, params['params'] ?? {}, context);
    _sendResult(id, result.toJson(), session.id);
  }

  Future<void> _handleListPrompts({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    final prompts = promptManager.listPrompts();
    _sendResult(id, {
      'prompts': prompts.map((p) => p.toJson()).toList(),
    }, session.id);
  }

  Future<void> _handleGetPrompt({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    final name = params['name'] as String?;
    if (name == null) {
      return _sendError(
        id: id,
        error: const McpError(
          code: McpError.invalidParams,
          message: "Missing required parameter: 'name'",
        ),
        sessionId: session.id,
      );
    }
    final handler = promptManager.getHandler(name);
    if (handler == null) {
      return _sendError(
        id: id,
        error: McpError(
          code: McpError.promptNotFound,
          message: "Prompt '$name' not found",
        ),
        sessionId: session.id,
      );
    }
    final context = McpContext(
      engine: this,
      session: session,
      operationId: id?.toString() ?? const Uuid().v4(),
      cancellationToken: const CancellationToken(false),
    );
    final result = await handler(params['arguments'] ?? {}, context);
    _sendResult(id, result.toJson(), session.id);
  }

  Future<void> _handleCancel({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    final operationId = params['operationId'] as String?;
    if (operationId != null) {
      log.info('Received cancellation request for operation: $operationId');
      operationManager.cancel(operationId);
    }
  }

  void _sendResult(dynamic id, dynamic result, String? sessionId) {
    if (id == null) return;

    final responseStream = _httpResponseMap.remove(id);

    final payload = {'jsonrpc': '2.0', 'id': id, 'result': result};

    if (responseStream != null) {
      payload['_http_response'] = responseStream;
    }

    _transport?.send(payload, sessionId: sessionId);
  }

  void _sendError({
    required dynamic id,
    required McpError error,
    String? sessionId,
  }) {
    if (id == null) return;
    final responseStream = _httpResponseMap.remove(id);
    final payload = {'jsonrpc': '2.0', 'id': id, 'error': error.toJson()};
    if (responseStream != null) {
      payload['_http_response'] = responseStream;
    }
    _transport?.send(payload, sessionId: sessionId);
  }

  void sendNotification({
    required String sessionId,
    required String method,
    required Map<String, dynamic> params,
  }) {
    final payload = {'jsonrpc': '2.0', 'method': method, 'params': params};
    final progressToken = params['progressToken'];

    if (method == McpProtocol.progress && progressToken != null) {
      final operation = operationManager.getOperationFromToken(progressToken);
      if (operation != null) {
        final responseStream = _httpResponseMap[operation.originalRequestId];
        if (responseStream != null) {
          payload['_http_response'] = responseStream;
        }
      }
    }
    _transport?.send(payload, sessionId: sessionId);
  }

  void dispose() {
    _transportSubscription?.cancel();
    sessionManager.dispose();
    _transport?.close();
    log.info('Engine disposed.');
  }
}
