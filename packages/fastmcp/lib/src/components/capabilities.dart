import 'package:meta/meta.dart';

@immutable
class ToolsCapability {
  final bool listChanged;
  final bool supportsProgress;
  final bool supportsCancellation;

  const ToolsCapability({
    this.listChanged = false,
    this.supportsProgress = false,
    this.supportsCancellation = false,
  });

  Map<String, dynamic> toJson() => {
    'listChanged': listChanged,
    'supportsProgress': supportsProgress,
    'supportsCancellation': supportsCancellation,
  };
}

@immutable
class ResourcesCapability {
  final bool listChanged;
  final bool subscribe;

  const ResourcesCapability({this.listChanged = false, this.subscribe = false});

  Map<String, dynamic> toJson() => {
    'listChanged': listChanged,
    'subscribe': subscribe,
  };
}

@immutable
class PromptsCapability {
  final bool listChanged;

  const PromptsCapability({this.listChanged = false});

  Map<String, dynamic> toJson() => {'listChanged': listChanged};
}

@immutable
class LoggingCapability {
  const LoggingCapability();

  Map<String, dynamic> toJson() => {};
}

@immutable
class SamplingCapability {
  const SamplingCapability();

  Map<String, dynamic> toJson() => {};
}

/// Defines the features supported by the MCP server.
///
/// In `fastmcp`, this object is typically constructed automatically by the
/// `McpEngine` based on the features you have implemented.
@immutable
class ServerCapabilities {
  final ToolsCapability? tools;
  final ResourcesCapability? resources;
  final PromptsCapability? prompts;
  final LoggingCapability? logging;
  final SamplingCapability? sampling;

  const ServerCapabilities({
    this.tools,
    this.resources,
    this.prompts,
    this.logging,
    this.sampling,
  });

  /// A convenience constructor for enabling a standard set of features.
  /// This is used as the default in `FastMCP`.
  factory ServerCapabilities.standard() => ServerCapabilities(
    tools: const ToolsCapability(
      listChanged: true,
      supportsProgress: true,
      supportsCancellation: true,
    ),
    resources: const ResourcesCapability(listChanged: true),
    prompts: const PromptsCapability(listChanged: true),
  );

  Map<String, dynamic> toJson() {
    return {
      if (tools != null) 'tools': tools!.toJson(),
      if (resources != null) 'resources': resources!.toJson(),
      if (prompts != null) 'prompts': prompts!.toJson(),
      if (logging != null) 'logging': logging!.toJson(),
      if (sampling != null) 'sampling': sampling!.toJson(),
    };
  }
}
