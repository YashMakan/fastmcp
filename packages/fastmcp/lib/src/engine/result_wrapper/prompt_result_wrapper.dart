import 'package:fastmcp/fastmcp.dart';

class PromptResultWrapper {
  static Future<PromptResult> wrap(
    dynamic potentialFuture, {
    required String promptName,
  }) async {
    final result = (potentialFuture is Future)
        ? await potentialFuture
        : potentialFuture;

    return switch (result) {
      // The only valid return type is PromptResult.
      PromptResult r => r,

      // Any other return type is a developer error.
      _ => throw StateError(
        'Prompt function "$promptName" must return an object of type GetPromptResult or Future<GetPromptResult>. '
        'Instead, it returned an object of type ${result.runtimeType}.',
      ),
    };
  }
}
