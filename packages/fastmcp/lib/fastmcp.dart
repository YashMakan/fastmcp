import 'package:fastmcp/src/components/capabilities.dart';
import 'package:fastmcp/src/components/tool.dart';
import 'package:fastmcp/src/engine/managers/prompt_manager.dart';
import 'package:fastmcp/src/engine/managers/resource_manager.dart';
import 'package:fastmcp/src/transport/http_transport.dart';

import 'src/components/prompt.dart';
import 'src/components/resource.dart';
import 'src/engine/mcp_engine.dart';
import 'src/engine/managers/tool_manager.dart';
import 'src/transport/transport.dart';

export 'src/annotations/param.dart';
export 'src/components/prompt.dart';
export 'src/components/resource.dart';
export 'src/components/tool.dart';
export 'src/engine/result_wrapper/prompt_result_wrapper.dart';
export 'src/engine/result_wrapper/resource_result_wrapper.dart';
export 'src/engine/result_wrapper/tool_result_wrapper.dart';
export 'src/models/content.dart';
export 'src/models/context.dart';
export 'src/models/results.dart';
export 'src/transport/http_transport.dart'
    show HttpTransport, HttpTransportConfig, HttpTransportMode;
export 'src/transport/stdio_transport.dart' show StdioTransport;
export 'src/transport/transport.dart' show ServerTransport;

class FastMCP {
  final McpEngine _engine;

  McpEngine get engine => _engine;

  FastMCP({
    required String name,
    String version = '1.0.0',
    ServerCapabilities? capabilities,
  }) : _engine = McpEngine(
         name: name,
         version: version,
         capabilities: capabilities ?? ServerCapabilities.standard(),
       );

  /// Starts the server and listens for requests.
  /// This method will not complete until the server is shut down.
  Future<void> run({
    required ServerTransport transport,
    required void Function(FastMCP app) registerGenerated,
  }) async {
    if (transport is HttpTransport) {
      transport.start();
    }

    engine.log.info('Registering generated functions...');
    registerGenerated(this);
    engine.log.info('Registration complete.');

    engine.connect(transport);
    engine.log.info('FastMCP server "${engine.name}" is running...');

    await transport.onClose;

    engine.dispose();
  }

  void registerTool({required Tool tool, required ToolHandler handler}) {
    _engine.toolManager.register(tool, handler);
  }

  void registerResource({
    required Resource resource,
    required ResourceHandler handler,
  }) {
    engine.resourceManager.register(resource, handler);
  }

  void registerPrompt({
    required Prompt prompt,
    required PromptHandler handler,
  }) {
    engine.promptManager.register(prompt, handler);
  }
}
