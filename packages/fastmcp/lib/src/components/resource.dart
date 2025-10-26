import 'package:meta/meta.dart';

/// Represents the content of a resource, used in the result of a resource handler.
@immutable
class ResourceContent {
  final String uri;
  final String? mimeType;
  final String? text;

  const ResourceContent({required this.uri, this.mimeType, this.text});

  Map<String, dynamic> toJson() {
    return {
      'uri': uri,
      if (mimeType != null) 'mimeType': mimeType,
      if (text != null) 'text': text,
    };
  }
}

/// The result returned from a resource handler function.
@immutable
class ReadResourceResult {
  final List<ResourceContent> contents;

  const ReadResourceResult({required this.contents});

  Map<String, dynamic> toJson() => {
    'contents': contents.map((c) => c.toJson()).toList(),
  };
}

/// Represents an MCP Resource, serving as both an annotation and a data model.
///
/// Use this as an annotation on functions that provide data. The function's
/// return value will be automatically wrapped.
///
/// Example:
/// ```dart
/// @Resource(uri: 'system://time', mimeType: 'text/plain')
/// String getCurrentTime() => DateTime.now().toIso8601String();
/// ```
@immutable
class Resource {
  final String uri;
  final String? name;
  final String? description;
  final String? mimeType;
  final bool register;
  final Map<String, dynamic> uriTemplate;
  final Map<String, dynamic>? meta;

  const Resource({
    required this.uri,
    this.name,
    this.description,
    this.mimeType,
    this.register = true,
    this.uriTemplate = const {},
    this.meta,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'uri': uri,
      'name': name ?? 'Unnamed Resource',
      'description': description ?? 'No description provided.',
      if (mimeType != null) 'mimeType': mimeType,
      if (uriTemplate.isNotEmpty) 'uriTemplate': uriTemplate,
    };
    if (meta != null) {
      json['_meta'] = meta;
    }
    return json;
  }
}
