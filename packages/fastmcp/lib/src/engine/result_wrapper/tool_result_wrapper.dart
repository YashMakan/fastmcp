import 'package:fastmcp/fastmcp.dart';

class ToolResultWrapper {
  static Future<CallToolResult> wrap(dynamic potentialFuture) async {
    final result = (potentialFuture is Future)
        ? await potentialFuture
        : potentialFuture;

    return switch (result) {
      // If the user already returned the correct type, pass it through.
      CallToolResult r => r,

      // If they returned a single Content object, wrap it in a list.
      Content c => CallToolResult(content: [c]),

      // If they returned a list of Content objects, use it directly.
      List<Content> lc => CallToolResult(content: lc),

      // If the result is null (e.g., from a void function), return an empty success.
      null => const CallToolResult(content: []),

      // For primitive types, provide the raw value in an annotation.
      num n => CallToolResult(
        content: [
          TextContent(text: n.toString(), annotations: {'value': n}),
        ],
      ),
      bool b => CallToolResult(
        content: [
          TextContent(text: b.toString(), annotations: {'value': b}),
        ],
      ),

      _ => CallToolResult(content: [TextContent(text: result.toString())]),
    };
  }
}
