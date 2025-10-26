import 'package:meta/meta.dart';

/// MCP Protocol Version constants and method names.
@immutable
class McpProtocol {
  static const String jsonRpcVersion = "2.0";
  static const String v2025_03_26 = "2025-03-26";
  static const List<String> supportedVersions = [v2025_03_26];

  // --- Core Method Names ---
  static const String initialize = 'initialize';

  // --- Tool Method Names ---
  static const String listTools = 'tools/list';
  static const String callTool = 'tools/call';

  // --- Resource Method Names (NEW) ---
  static const String listResources = 'resources/list';
  static const String readResource = 'resources/read';

  // --- Prompt Method Names (NEW) ---
  static const String listPrompts = 'prompts/list';
  static const String getPrompt = 'prompts/get';

  // --- Operation Method Names ---
  static const String cancel = 'operations/cancel';
  static const String progress = 'notifications/progress';
}
