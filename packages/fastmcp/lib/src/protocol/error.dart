import 'package:meta/meta.dart';

/// Standardized MCP error structure.
@immutable
class McpError {
  final int code;
  final String message;
  final dynamic data;

  const McpError({required this.code, required this.message, this.data});

  // --- JSON-RPC Standard Codes ---
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  // --- MCP Specific Codes ---
  static const int toolNotFound = -32101;
  static const int resourceNotFound = -32100;
  static const int promptNotFound = -32102;

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };
}
