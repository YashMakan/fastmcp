import 'package:meta/meta.dart';

/// Represents an MCP Tool, serving as both an annotation and a data model.
///
/// Use this as an annotation on your functions:
/// ```dart
/// @Tool(description: 'My awesome tool.')
/// String myTool() => 'Hello';
/// ```
@immutable
class Tool {
  /// The official name of the tool for the MCP protocol.
  /// If null when used as an annotation, the generator infers it from the function name.
  final String? name;

  /// A description of what the tool does.
  /// If null, the generator will attempt to use the function's doc comment.
  final String? description;

  /// Set to false to prevent the generator from registering this tool.
  final bool register;

  /// The JSON schema defining the tool's input arguments.
  /// This is typically generated automatically from the function's parameters.
  final Map<String, dynamic> inputSchema;

  final Map<String, dynamic>? meta;

  final List<Map<String, dynamic>>? securitySchemes;

  const Tool({
    this.name,
    this.description,
    this.register = true,
    this.meta,
    this.inputSchema = const {},
    this.securitySchemes,
  });

  Tool copyWith({
    String? name,
    String? description,
    Map<String, dynamic>? inputSchema,
  }) {
    return Tool(
      name: name ?? this.name,
      description: description ?? this.description,
      inputSchema: inputSchema ?? this.inputSchema,
      register: register,
    );
  }

  Map<String, dynamic> toJson() {
    final json = {
      'name': name!,
      'description': description ?? 'No description provided.',
      'inputSchema': inputSchema,
    };
    if (meta != null) {
      json['_meta'] = meta!;
    }
    if (securitySchemes != null) {
      json['securitySchemes'] = securitySchemes!;
    }
    return json;
  }
}
