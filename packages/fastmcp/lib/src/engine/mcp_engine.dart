// packages/fastmcp/lib/src/engine/mcp_engine.dart (Corrected)

import 'dart:async';
import 'dart:io';

import 'package:fastmcp/src/components/capabilities.dart';
import 'package:fastmcp/src/models/context.dart';
import 'package:fastmcp/src/models/session.dart';
import 'package:fastmcp/src/protocol/error.dart';
import 'package:fastmcp/src/protocol/protocol.dart';
import 'package:fastmcp/src/transport/http_transport.dart';
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

  McpEngine({
    required this.name,
    required this.version,
    required this.capabilities,
  }) {
    _methodRouter = {
      McpProtocol.initialize: _handleInitialize,
      McpProtocol.ping: _handlePing,
      'notifications/initialized':
          _handleInitializedNotification, // ADD THIS HANDLER
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
    if (transport is HttpTransport) {
      transport.setEngine(this);
    }
    _transportSubscription = transport.onMessage.listen(_dispatchMessage);
    log.info('Engine connected to transport.');
  }

  // CORRECTED DISPATCH LOGIC
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

    ClientSession session;
    if (method == McpProtocol.initialize) {
      // MODIFIED: Pass the sessionId from the transport event to createSession.
      // In HTTP/SSE, this ID was generated during the GET request and passed
      // back via the POST query param.
      session = sessionManager.createSession(
        id: event.sessionId,
        clientInfo:
            (message['params'] as Map<String, dynamic>?)?['clientInfo'] ?? {},
        protocolVersion:
            (message['params'] as Map<String, dynamic>?)?['protocolVersion'] ??
            McpProtocol.v2025_03_26,
      );

      // Associate the transportId with the session.
      // For HttpTransport, transportId and session.id are now identical, which is fine.
      _transport?.associateSession(event.transportId, session.id);
    } else {
      // For all other methods, a session MUST already exist.
      final existingSession = sessionManager.getSession(event.sessionId);
      if (existingSession == null) {
        _sendError(
          id: id,
          error: McpError(
            code: McpError.invalidRequest,
            message: "Session not initialized or has expired. Method: $method",
          ),
          sessionId: event.sessionId,
        );
        return;
      }
      session = existingSession;
    }

    final handler = _methodRouter[method];
    if (handler == null) {
      _sendError(
        id: id,
        error: McpError(
          code: McpError.methodNotFound,
          message: "Method '$method' not found",
        ),
        sessionId: session.id,
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
        sessionId: session.id,
      );
    }
  }

  // This handler now only sends the response. Session creation happens in dispatch.
  Future<void> _handleInitialize({
    required TransportMessage event,
    required ClientSession session, // This is the REAL, newly created session.
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    _sendResult(id, {
      'protocolVersion': session.protocolVersion,
      'serverInfo': {'name': name, 'version': version},
      'capabilities': capabilities.toJson(),
    }, session.id);
  }

  // NEW: Handler for the client's confirmation notification.
  Future<void> _handleInitializedNotification({
    required TransportMessage event,
    required ClientSession session,
    required Map<String, dynamic> params,
    required dynamic id,
  }) async {
    log.info(
      'Client confirmed session initialization for session: ${session.id}',
    );
    // Per the spec, the server replies with 202 Accepted and no body.
    // The transport layer is responsible for sending the correct HTTP status code.
    // We signal this by sending a null result for a null ID (notification).
    _sendResult(id, null, session.id);
  }

  // --- The rest of the handlers are unchanged ---
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
    // A null ID indicates a notification, which doesn't have a result in its response.
    if (id == null) {
      _transport?.send(
        null,
        sessionId: sessionId,
      ); // Signal to transport to send 202 Accepted
      return;
    }
    _transport?.send({
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    }, sessionId: sessionId);
  }

  void _sendError({
    required dynamic id,
    required McpError error,
    String? sessionId,
  }) {
    if (id == null) return;
    _transport?.send({
      'jsonrpc': '2.0',
      'id': id,
      'error': error.toJson(),
    }, sessionId: sessionId);
  }

  void sendNotification({
    required String sessionId,
    required String method,
    required Map<String, dynamic> params,
  }) {
    final payload = {'jsonrpc': '2.0', 'method': method, 'params': params};
    _transport?.send(payload, sessionId: sessionId);
  }

  void dispose() {
    _transportSubscription?.cancel();
    sessionManager.dispose();
    _transport?.close();
    log.info('Engine disposed.');
  }
}
