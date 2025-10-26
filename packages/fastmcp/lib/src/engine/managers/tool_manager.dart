import 'dart:async';

import 'package:fastmcp/fastmcp.dart';

typedef ToolHandler =
    Future<CallToolResult> Function(
      Map<String, dynamic> arguments,
      McpContext context,
    );

class ToolManager {
  final Map<String, Tool> _tools = {};
  final Map<String, ToolHandler> _handlers = {};

  void register(Tool tool, ToolHandler handler) {
    _tools[tool.name!] = tool;
    _handlers[tool.name!] = handler;
  }

  Tool? getTool(String name) => _tools[name];

  List<Tool> listTools() => _tools.values.toList();

  ToolHandler? getHandler(String name) => _handlers[name];
}
