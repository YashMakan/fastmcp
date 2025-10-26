// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'main.dart';

// **************************************************************************
// FastMcpGenerator
// **************************************************************************

void registerGenerated(FastMCP app) {
  app.registerTool(
    tool: Tool(
      name: 'greeting',
      description:
          'A versatile greeting tool that demonstrates different parameter types.',
      meta: {
        'author': 'FastMCP Team',
        'version': '1.1.0',
        'tags': ['communication', 'example']
      },
      inputSchema: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'The primary name for the greeting.'
          },
          'title': {
            'type': 'string',
            'description': 'An optional title, like "Dr." or "Mx.".'
          },
          'formal': {
            'type': 'boolean',
            'description': 'If true, the greeting will be more formal.'
          },
        },
        'required': ['name'],
      },
    ),
    handler: (args, context) async {
      try {
        final nameArg = args['name'];
        if (nameArg == null) {
          throw ArgumentError('Missing required parameter: "name"');
        }
        final name = nameArg as String;
        final titleArg = args['title'];
        final title = titleArg == null ? null : titleArg as String;
        final formalArg = args['formal'];
        final formal = formalArg == null ? false : formalArg as bool;

        final result =
            generateGreeting(name: name, title: title, formal: formal);
        return ToolResultWrapper.wrap(result);
      } catch (e, s) {
        print('Error executing tool "greeting": $e\n$s');
        return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Tool execution failed: $e')]);
      }
    },
  );
  app.registerTool(
    tool: Tool(
      name: 'processData',
      description:
          'A long-running tool that demonstrates progress reporting and cancellation.',
      meta: null,
      inputSchema: {
        'type': 'object',
        'properties': {
          'steps': {
            'type': 'number',
            'description': 'The number of steps to simulate.'
          },
        },
        'required': [],
      },
    ),
    handler: (args, context) async {
      try {
        final stepsArg = args['steps'];
        final steps = stepsArg == null ? 10 : (stepsArg as num).toInt();

        final result = processData(context, steps: steps);
        return ToolResultWrapper.wrap(result);
      } catch (e, s) {
        print('Error executing tool "processData": $e\n$s');
        return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Tool execution failed: $e')]);
      }
    },
  );
  app.registerResource(
    resource: Resource(
      uri: 'server://time',
      name: 'Server Time',
      description: 'Gets the current server time in ISO 8601 format.',
      mimeType: 'text/plain',
      meta: {'rate_limited': false, 'visibility': 'public'},
    ),
    handler: (uri, params, context) async {
      try {
        final result = getCurrentTime();
        return ResourceResultWrapper.wrap(result,
            uri: 'server://time', mimeType: 'text/plain');
      } catch (e, s) {
        print('Error executing resource "server://time": $e\n$s');
        return const ReadResourceResult(contents: []);
      }
    },
  );
  app.registerPrompt(
    prompt: Prompt(
      name: 'code-review-prompt',
      description: 'Generates a system prompt for an AI code reviewer.',
      arguments: [
        {
          'name': 'language',
          'description': 'The programming language of the code to be reviewed.',
          'required': true,
        },
        {
          'name': 'expertiseLevel',
          'description': 'No description provided.',
          'required': false,
          'default': 'senior',
        }
      ],
    ),
    handler: (args, context) async {
      try {
        final languageArg = args['language'];
        if (languageArg == null) {
          throw ArgumentError('Missing required parameter: "language"');
        }
        final language = languageArg as String;
        final expertiseLevelArg = args['expertiseLevel'];
        final expertiseLevel =
            expertiseLevelArg == null ? 'senior' : expertiseLevelArg as String;

        final result = createCodeReviewPrompt(
            language: language, expertiseLevel: expertiseLevel);
        return PromptResultWrapper.wrap(result,
            promptName: 'code-review-prompt');
      } catch (e, s) {
        print('Error executing prompt "code-review-prompt": $e\n$s');
        throw e;
      }
    },
  );
}
