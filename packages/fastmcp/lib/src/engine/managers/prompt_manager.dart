import 'dart:async';

import 'package:fastmcp/fastmcp.dart';

typedef PromptHandler =
    Future<PromptResult> Function(
      Map<String, dynamic> arguments,
      McpContext context,
    );

class PromptManager {
  final Map<String, Prompt> _prompts = {};
  final Map<String, PromptHandler> _handlers = {};

  void register(Prompt prompt, PromptHandler handler) {
    _prompts[prompt.name] = prompt;
    _handlers[prompt.name] = handler;
  }

  PromptHandler? getHandler(String name) => _handlers[name];

  List<Prompt> listPrompts() => _prompts.values.toList();
}
