import 'dart:async';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart' hide Resource;
import 'package:fastmcp/fastmcp.dart';
import 'package:source_gen/source_gen.dart';

class FastMcpGenerator extends Generator {
  const FastMcpGenerator();

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) {
    final buffer = StringBuffer();
    final toolChecker = const TypeChecker.fromRuntime(Tool);
    final resourceChecker = const TypeChecker.fromRuntime(Resource);
    final promptChecker = const TypeChecker.fromRuntime(Prompt);

    final tools = library.annotatedWith(toolChecker);
    final resources = library.annotatedWith(resourceChecker);
    final prompts = library.annotatedWith(promptChecker);

    if (tools.isEmpty && resources.isEmpty && prompts.isEmpty) {
      return null;
    }

    buffer.writeln('void registerGenerated(FastMCP app) {');

    for (final annotatedElement in tools) {
      buffer.writeln(
        _generateTool(annotatedElement.element, annotatedElement.annotation),
      );
    }
    for (final annotatedElement in resources) {
      buffer.writeln(
        _generateResource(
          annotatedElement.element,
          annotatedElement.annotation,
        ),
      );
    }
    for (final annotatedElement in prompts) {
      buffer.writeln(
        _generatePrompt(annotatedElement.element, annotatedElement.annotation),
      );
    }

    buffer.writeln('}');
    return buffer.toString();
  }

  String? _getMetaSource(ConstantReader annotation) {
    final metaField = annotation.peek('meta');
    if (metaField == null || metaField.isNull) return null;

    final metaObject = metaField.objectValue;
    return _dartObjectToLiteral(metaObject);
  }

  String _dartObjectToLiteral(DartObject? obj) {
    if (obj == null) return 'null';

    if (obj.isNull) return 'null';

    final type = obj.type?.getDisplayString(withNullability: false);

    if (obj.toBoolValue() != null) return obj.toBoolValue().toString();
    if (obj.toIntValue() != null) return obj.toIntValue().toString();
    if (obj.toDoubleValue() != null) return obj.toDoubleValue().toString();
    if (obj.toStringValue() != null) {
      final escaped = obj.toStringValue()!.replaceAll("'", "\\'");
      return "'$escaped'";
    }

    final list = obj.toListValue();
    if (list != null) {
      final elements = list.map(_dartObjectToLiteral).join(', ');
      return '[$elements]';
    }

    final map = obj.toMapValue();
    if (map != null) {
      final entries = map.entries
          .map((e) =>
      '${_dartObjectToLiteral(e.key)}: ${_dartObjectToLiteral(e.value)}')
          .join(', ');
      return '{ $entries }';
    }

    return "'$type'";
  }

  String _generateTool(Element element, ConstantReader annotation) {
    if (element is! FunctionElement) return '';
    if (element.isPrivate || annotation.read('register').boolValue == false) {
      return '';
    }

    final finalToolName =
        annotation.read('name').literalValue as String? ?? element.name;
    final docComment = element.documentationComment
        ?.replaceAll('///', '')
        .trim();
    final description =
        annotation.read('description').literalValue as String? ??
        docComment ??
        'No description provided.';
    final escapedDescription = description
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n');

    final metaSource = _getMetaSource(annotation) ?? 'null';

    final schemaBuffer = StringBuffer();
    final handlerBuffer = StringBuffer();
    final requiredParams = <String>[];
    _buildArgsAndSchema(element, schemaBuffer, handlerBuffer, requiredParams);

    final functionCall = "${element.name}(${_generateFunctionCall(element)})";
    final returnLogic = element.returnType.isVoid
        ? '$functionCall; return const CallToolResult(content: []);'
        : 'final result = $functionCall; return ToolResultWrapper.wrap(result);';

    return '''
      app.registerTool(
        tool: Tool(
          name: '$finalToolName',
          description: '$escapedDescription',
          meta: $metaSource,
          inputSchema: {'type': 'object','properties': {${schemaBuffer.toString()}},'required': [${requiredParams.map((p) => "'$p'").join(', ')}],},
        ),
        handler: (args, context) async {
          try {
            ${handlerBuffer.toString()}
            $returnLogic
          } catch (e, s) {
            print('Error executing tool "$finalToolName": \$e\\n\$s');
            return CallToolResult(isError: true, content: [TextContent(text: 'Tool execution failed: \$e')]);
          }
        },
      );''';
  }

  String _generateResource(Element element, ConstantReader annotation) {
    if (element is! FunctionElement) return '';
    if (element.isPrivate || annotation.read('register').boolValue == false) {
      return '';
    }

    final uri = annotation.read('uri').stringValue;
    final name =
        annotation.read('name').literalValue as String? ?? element.name;
    final docComment = element.documentationComment
        ?.replaceAll('///', '')
        .trim();
    final metaSource = _getMetaSource(annotation) ?? 'null';
    final description =
        annotation.read('description').literalValue as String? ??
        docComment ??
        'No description provided.';
    final escapedDescription = description
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n');
    final mimeType = annotation.read('mimeType').literalValue as String?;

    final functionCall = "${element.name}()";

    final returnLogic =
        '''
      final result = $functionCall;
      return ResourceResultWrapper.wrap(result, uri: '$uri', mimeType: ${mimeType == null ? 'null' : "'$mimeType'"});
    ''';

    return '''
      app.registerResource(
        resource: Resource(
          uri: '$uri',
          name: '$name',
          description: '$escapedDescription',
          mimeType: ${mimeType == null ? 'null' : "'$mimeType'"},
          meta: $metaSource,
        ),
        handler: (uri, params, context) async {
          try {
            $returnLogic
          } catch (e, s) {
            print('Error executing resource "$uri": \$e\\n\$s');
            return const ReadResourceResult(contents: []); 
          }
        },
      );''';
  }
}

String _generatePrompt(Element element, ConstantReader annotation) {
  if (element is! FunctionElement) return '';
  if (element.isPrivate || annotation.read('register').boolValue == false) {
    return '';
  }

  final argumentSchemaList = <String>[];
  final handlerBuffer = StringBuffer();
  _buildArgsAndSchema(
    element,
    null,
    handlerBuffer,
    [],
    argumentSchemaList: argumentSchemaList,
  );

  final docComment = element.documentationComment?.replaceAll('///', '').trim();

  final name = annotation.read('name').stringValue;

  final description =
      annotation.read('description').literalValue as String? ??
      docComment ??
      'No description provided.';
  final escapedDescription = description
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n');

  final functionCall = "${element.name}(${_generateFunctionCall(element)})";

  final returnLogic =
      '''
      final result = $functionCall;
      return PromptResultWrapper.wrap(result, promptName: '$name');
    ''';

  return '''
      app.registerPrompt(
        prompt: Prompt(
          name: '$name',
          description: '$escapedDescription',
          arguments: [${argumentSchemaList.join(',\n')}],
        ),
        handler: (args, context) async {
          try {
            ${handlerBuffer.toString()}
            $returnLogic
          } catch (e, s) {
            print('Error executing prompt "$name": \$e\\n\$s');
            throw e;
          }
        },
      );''';
}

void _buildArgsAndSchema(
  FunctionElement element,
  StringBuffer? schemaBuffer,
  StringBuffer handlerBuffer,
  List<String> requiredParams, {
  List<String>? argumentSchemaList,
}) {
  const paramChecker = TypeChecker.fromRuntime(Param);
  for (final param in element.parameters) {
    final paramName = param.name;
    final type = param.type;
    final typeName = type.getDisplayString(withNullability: false);

    if (typeName == 'McpContext') continue;

    String? paramDescription;
    if (paramChecker.hasAnnotationOfExact(param)) {
      final annotation = paramChecker.firstAnnotationOfExact(param)!;
      final reader = ConstantReader(annotation);
      paramDescription = reader.read('description').literalValue as String?;
    }
    paramDescription ??= _getDocumentationForParameter(param);
    paramDescription ??= 'No description provided.';
    final escapedDescription = paramDescription
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n');

    final schemaType = _mapDartTypeToJsonSchema(typeName);
    schemaBuffer?.writeln(
      "'$paramName': {'type': '$schemaType', 'description': '$escapedDescription'},",
    );

    final isTrulyRequired =
        param.isRequiredNamed || (param.isPositional && !param.isOptional);
    if (isTrulyRequired) {
      requiredParams.add(paramName);
    }

    argumentSchemaList?.add(
      "{'name': '$paramName','description': '$escapedDescription','required': $isTrulyRequired, ${param.hasDefaultValue ? "'default': ${param.defaultValueCode}," : ""}}",
    );

    handlerBuffer.writeln("final ${paramName}Arg = args['$paramName'];");
    if (isTrulyRequired) {
      handlerBuffer.writeln(
        "if (${paramName}Arg == null) { throw ArgumentError('Missing required parameter: \"$paramName\"'); }",
      );
      handlerBuffer.writeln(
        "final $paramName = ${_generateTypeConversion(typeName, '${paramName}Arg', false)};",
      );
    } else {
      handlerBuffer.writeln(
        "final $paramName = ${paramName}Arg == null ? ${param.hasDefaultValue ? param.defaultValueCode : 'null'} : ${_generateTypeConversion(typeName, '${paramName}Arg', false)};",
      );
    }
  }
}

String? _getDocumentationForParameter(ParameterElement parameter) {
  final unit = parameter.thisOrAncestorOfType<CompilationUnitElement>();
  if (unit == null) return null;
  final source = parameter.source?.contents.data;
  if (source == null) return null;
  final lineInfo = unit.lineInfo;
  final parameterLineNumber = lineInfo
      .getLocation(parameter.nameOffset)
      .lineNumber;
  final sourceLines = source.split('\n');
  final commentLines = <String>[];
  for (int i = parameterLineNumber - 2; i >= 0; i--) {
    final lineText = sourceLines[i].trim();
    if (lineText.startsWith('///')) {
      commentLines.insert(0, lineText.substring(3).trim());
    } else {
      break;
    }
  }
  return commentLines.isNotEmpty ? commentLines.join('\n') : null;
}

String _generateTypeConversion(
  String typeName,
  String varName,
  bool isNullable,
) {
  String conversion;
  switch (typeName) {
    case 'String':
      conversion = "$varName as String";
      break;
    case 'int':
      conversion = "($varName as num).toInt()";
      break;
    case 'double':
      conversion = "($varName as num).toDouble()";
      break;
    case 'num':
      conversion = "$varName as num";
      break;
    case 'bool':
      conversion = "$varName as bool";
      break;
    default:
      conversion = "$varName as $typeName";
  }
  if (isNullable) return "$varName == null ? null : ($conversion)";
  return conversion;
}

String _mapDartTypeToJsonSchema(String dartType) {
  switch (dartType) {
    case 'String':
      return 'string';
    case 'int':
    case 'double':
    case 'num':
      return 'number';
    case 'bool':
      return 'boolean';
    default:
      return 'object';
  }
}

String _generateFunctionCall(FunctionElement element) {
  return element.parameters
      .map((p) {
        final typeName = p.type.getDisplayString(withNullability: false);
        final varName = typeName == 'McpContext' ? 'context' : p.name;
        if (p.isNamed) return '${p.name}: $varName';
        return varName;
      })
      .join(', ');
}
