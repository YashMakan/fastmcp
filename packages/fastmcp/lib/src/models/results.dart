import 'package:meta/meta.dart';

import 'content.dart';

/// The result of a successful tool call.
@immutable
class CallToolResult {
  final List<Content> content;
  final bool isError;
  final Map<String, dynamic>? meta;

  const CallToolResult({
    this.content = const [],
    this.isError = false,
    this.meta,
  });

  Map<String, dynamic> toJson() => {
    'content': content.map((c) => c.toJson()).toList(),
    if (isError) 'isError': isError,
    if (meta != null) '_meta': meta,
  };
}
