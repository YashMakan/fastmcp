import 'package:fastmcp/fastmcp.dart';

part 'main.fastmcp.g.dart';

// 1. Create the main application instance.
final mcp = FastMCP(name: 'FastMCP Showcase Server', version: '1.0.0');

// =======================================================================
// TOOL EXAMPLES
// =======================================================================

/// A versatile greeting tool that demonstrates different parameter types.
@Tool(
  name: 'greeting',
  meta: {
    'author': 'FastMCP Team',
    'version': '1.1.0',
    'tags': ['communication', 'example'],
  },
)
String generateGreeting({
  /// The name of the person to greet.
  @Param(description: 'The primary name for the greeting.')
  required String name,

  /// An optional title, like "Dr." or "Mx.".
  String? title,

  /// If true, the greeting will be more formal.
  bool formal = false,
}) {
  final greeting = formal ? 'Good day' : 'Hello';
  final titledName = title != null ? '$title $name' : name;
  return '$greeting, $titledName!';
}

/// A long-running tool that demonstrates progress reporting and cancellation.
@Tool()
Future<String> processData(
  McpContext context, {

  /// The number of steps to simulate.
  int steps = 10,
}) async {
  print(
    'Starting a long task with ${steps} steps for session ${context.session.id}...',
  );
  for (int i = 1; i <= steps; i++) {
    // Check if the client has requested to cancel this operation.
    if (context.cancellationToken.isCancelled) {
      final message = 'Task cancelled at step $i.';
      print(message);
      return message;
    }
    // Simulate doing some work.
    await Future.delayed(const Duration(seconds: 1));
    // Report progress back to the client.
    context.onProgress(i / steps, 'Completed step $i of $steps');
    print('  ... progress ${i / steps}');
  }
  return 'Processing complete after $steps steps.';
}

// =======================================================================
// RESOURCE EXAMPLES
// =======================================================================

/// A simple resource that provides the server's current time.
/// The return `String` is automatically wrapped into a `ReadResourceResult`.
@Resource(
  uri: 'server://time',
  name: 'Server Time',
  description: 'Gets the current server time in ISO 8601 format.',
  mimeType: 'text/plain',
  meta: {
    'rate_limited': false,
    'visibility': 'public',
  },
)
String getCurrentTime() => DateTime.now().toIso8601String();

// =======================================================================
// PROMPT EXAMPLES
// =======================================================================

/// A dynamic prompt for generating a system message for a code reviewer AI.
@Prompt(
  name: 'code-review-prompt',
  description: 'Generates a system prompt for an AI code reviewer.',
)
PromptResult createCodeReviewPrompt({
  @Param(description: 'The programming language of the code to be reviewed.')
  required String language,
  String expertiseLevel = 'senior',
}) {
  return PromptResult(
    description:
        'A system prompt for a $expertiseLevel $language code reviewer.',
    messages: [
      Message(
        role: 'system',
        content: TextContent(
          text:
              'You are a helpful and constructive AI assistant. '
              'You are acting as a $expertiseLevel software engineer who is an expert in the $language programming language. '
              'When you are asked to review code, provide feedback that is clear, actionable, and polite. '
              'Focus on best practices, potential bugs, and code readability.',
        ),
      ),
    ],
  );
}

void main() async {
  mcp.engine.sessionManager.onConnect.listen((session) {
    print(
      '✅ Client connected! Session ID: ${session.id}, Info: ${session.clientInfo}',
    );
  });

  mcp.engine.sessionManager.onDisconnect.listen((session) {
    print('❌ Client disconnected. Session ID: ${session.id}');
  });

  await mcp.run(
    registerGenerated: registerGenerated,
    transport: HttpTransport.streamable(port: 8080),
  );
}
