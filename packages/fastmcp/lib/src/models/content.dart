import 'package:meta/meta.dart';

/// Base class for all MCP content types, representing a piece of information
/// in a message or tool result.
@immutable
abstract class Content {
  const Content();

  /// Converts the content object to a JSON-encodable map, adhering to the MCP specification.
  Map<String, dynamic> toJson();
}

/// Represents a piece of textual information.
///
/// This is the most common content type, used for simple text responses. It can
/// optionally include structured `annotations` for machine-readable data.
@immutable
class TextContent extends Content {
  /// The human-readable text content.
  final String text;

  /// An optional map of structured, machine-readable data that supplements the text.
  ///
  /// This is the idiomatic way in MCP to provide typed values (like numbers or booleans)
  /// alongside their string representation.
  final Map<String, dynamic>? annotations;

  const TextContent({required this.text, this.annotations});

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': 'text', 'text': text};
    if (annotations != null) {
      json['annotations'] = annotations;
    }
    return json;
  }
}

/// Represents an image.
///
/// The image data should be provided as a Base64-encoded string, which is the
/// standard for embedding binary data in JSON payloads.
@immutable
class ImageContent extends Content {
  /// The Base64-encoded image data.
  final String data;

  /// The MIME type of the image (e.g., 'image/png', 'image/jpeg').
  final String mimeType;

  /// Optional structured metadata about the image.
  final Map<String, dynamic>? annotations;

  const ImageContent({
    required this.data,
    required this.mimeType,
    this.annotations,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': 'image',
      'data': data,
      'mimeType': mimeType,
    };
    if (annotations != null) {
      json['annotations'] = annotations;
    }
    return json;
  }
}
