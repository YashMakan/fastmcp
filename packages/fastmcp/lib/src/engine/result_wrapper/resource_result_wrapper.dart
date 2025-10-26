import 'package:fastmcp/fastmcp.dart';

class ResourceResultWrapper {
  static Future<ReadResourceResult> wrap(
    dynamic potentialFuture, {
    required String uri,
    String? mimeType,
  }) async {
    final result = (potentialFuture is Future)
        ? await potentialFuture
        : potentialFuture;

    return switch (result) {
      // If the user already returned the correct type, pass it through.
      ReadResourceResult r => r,

      // If they returned a single ResourceContent object, wrap it in a list.
      ResourceContent c => ReadResourceResult(contents: [c]),

      // If they returned a list of ResourceContent objects, use it directly.
      List<ResourceContent> lc => ReadResourceResult(contents: lc),

      // If the result is null, return an empty success.
      null => const ReadResourceResult(contents: []),

      // For anything else, convert to string and wrap in a single ResourceContent.
      _ => ReadResourceResult(
        contents: [
          ResourceContent(
            uri: uri,
            mimeType: mimeType,
            text: result.toString(),
          ),
        ],
      ),
    };
  }
}
