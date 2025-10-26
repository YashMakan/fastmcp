import 'package:meta/meta.dart';

import 'content.dart';

/// The result of a successful tool call.
@immutable
class CallToolResult {
  final List<Content> content;
  final bool isError;

  const CallToolResult({this.content = const [], this.isError = false});

  Map<String, dynamic> toJson() => {
    'content': content.map((c) => c.toJson()).toList(),
    if (isError) 'isError': isError,
  };
}
