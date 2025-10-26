import 'dart:async';

import 'package:fastmcp/fastmcp.dart';

typedef ResourceHandler =
    Future<ReadResourceResult> Function(
      String uri,
      Map<String, dynamic> params,
      McpContext context,
    );

class ResourceManager {
  final Map<String, Resource> _resources = {};
  final Map<String, ResourceHandler> _handlers = {};

  void register(Resource resource, ResourceHandler handler) {
    _resources[resource.uri] = resource;
    _handlers[resource.uri] = handler;
  }

  ResourceHandler? getHandler(String uri) => _handlers[uri];

  List<Resource> listResources() => _resources.values.toList();
}
