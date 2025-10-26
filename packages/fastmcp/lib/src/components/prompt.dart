import 'package:meta/meta.dart';

import '../models/content.dart';

/// Represents a single message in a prompt sequence (e.g., system, user, assistant).
@immutable
class Message {
  final String role;
  final Content content;

  const Message({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content.toJson()};
}

/// The result returned from a prompt handler function.
@immutable
class PromptResult {
  final String description;
  final List<Message> messages;

  const PromptResult({required this.description, required this.messages});

  Map<String, dynamic> toJson() => {
    'description': description,
    'messages': messages.map((m) => m.toJson()).toList(),
  };
}

/// Represents an MCP Prompt, serving as both an annotation and a data model.
///
/// Use this as an annotation on functions that generate prompt templates.
/// The function must return a `PromptResult`.
///
/// Example:
/// ```dart
/// @Prompt(name: 'code-review', description: 'Generates a code review prompt.')
/// PromptResult createReviewPrompt({required String language}) {
///   // ...
/// }
/// ```
@immutable
class Prompt {
  // --- Annotation Properties ---
  final String name;
  final String? description;
  final bool register;

  // --- Data Model Properties (for generator use) ---
  final List<Map<String, dynamic>> arguments;

  const Prompt({
    required this.name,
    this.description,
    this.register = true,
    this.arguments = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description ?? 'No description provided.',
    'arguments': arguments,
  };
}
