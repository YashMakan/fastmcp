import 'package:meta/meta.dart';

/// Annotation for providing metadata about a tool's parameter.
///
/// Use this on parameters within a function annotated with `@Tool`.
///
/// Example:
/// ```dart
/// @Tool()
/// String greet({@Param(description: 'The user's first name') required String name}) {
///   // ...
/// }
/// ```
@immutable
class Param {
  /// A description of the parameter for the JSON schema.
  final String? description;

  const Param({this.description});
}
