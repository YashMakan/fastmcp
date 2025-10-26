# FastMCP 🚀

[![Pub Version](https://img.shields.io/pub/v/fastmcp?style=for-the-badge&logo=dart&logoColor=white)](https://pub.dev/packages/fastmcp)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Style: lint](https://img.shields.io/badge/style-lint-40c4ff.svg?style=for-the-badge)](https://pub.dev/packages/lints)

**A fast, declarative, and type-safe server framework for the Model Context Protocol (MCP), inspired by [FastMCP(Python)](https://github.com/jlowin/fastmcp).**

Build powerful, production-ready MCP servers in Dart with minimal boilerplate. `fastmcp` uses modern language features and code generation to let you focus on your application logic, not the protocol details.

-   **⚡️ Blazing Fast Development:** Define MCP Tools, Resources, and Prompts as simple Dart functions using intuitive annotations.
-   **🔒 Type-Safe by Design:** The code generator automatically creates argument parsing and validation, eliminating manual casting and runtime errors.
-   **🤖 Automatic Schema Generation:** Your function signatures are automatically converted into compliant JSON schemas for tools and prompts.
-   **✨ Advanced Features, Simple API:** Built-in support for long-running tasks, progress reporting, and cancellation via a clean `McpContext` object.
-   **💎 Modern & Compliant:** Implements the latest MCP `2025-06-18` specification with a clean, modular architecture.
-   **🔌 Pluggable Transports:** Start with a simple `StdioTransport` for local development or use the production-ready `HttpTransport` for networked applications.

## 📚 Table of Contents

-   [🚀 Getting Started](#-getting-started)
    -   [1. Installation](#1-installation)
    -   [2. Create Your First Tool](#2-create-your-first-tool)
    -   [3. Run the Code Generator](#3-run-the-code-generator)
    -   [4. Run Your Server](#4-run-your-server)
-   [✨ Features](#-features)
    -   [Defining Resources](#defining-resources)
    -   [Defining Prompts](#defining-prompts)
    -   [Long-Running Tasks with `McpContext`](#long-running-tasks-with-mcpcontext)
    -   [Declarative Caching](#declarative-caching)
    -   [Custom Metadata](#custom-metadata)
-   [🤝 Contributing](#-contributing)
-   [✍️ Author](#️-author)
-   [📜 License](#-license)

## 🚀 Getting Started

### 1. Installation

You'll need `fastmcp` for the core framework and `fastmcp_generator` + `build_runner` for code generation.

```bash
# Add to your pubspec.yaml dependencies
dart pub add fastmcp

# Add to your pubspec.yaml dev_dependencies
dart pub add --dev build_runner
dart pub add --dev fastmcp_generator
```

### 2. Create Your First Tool

In your `main.dart` (or any library file), create a `FastMCP` instance and annotate a function.

```dart
import 'package:fastmcp/fast_mcp.dart';
part 'main.fastmcp.g.dart';

final app = FastMCP(name: 'MyFirstServer');

/// A simple tool that greets a user.
/// The doc comment is automatically used as the tool's description.
@Tool()
String greet({
    /// This description will auto assigned to the parameter
    required String name
}) {
  return 'Hello, $name!';
}

void main() async {
  await app.run(
    registerGenerated: registerGenerated,
    transport: StdioTransport(),
  );
}
```

### 3. Run the Code Generator

From your project's root directory, run `build_runner`.

```bash
dart run build_runner build
```

This will generate the `main.fastmcp.g.dart` file, containing all the necessary boilerplate to connect your `greet` function to the MCP engine.

### 4. Run Your Server

That's it! Run your application.
```bash
$fastmcp/example dart run lib/main.dart
[INFO] 03:11:24.875 [McpEngine]: Registering generated functions...
[INFO] 03:11:24.877 [McpEngine]: Registration complete.
[INFO] 03:11:24.878 [McpEngine]: Engine connected to transport.
[INFO] 03:11:24.878 [McpEngine]: FastMCP server "FastMCP Showcase Server" is running...
[INFO] 03:11:24.884 [HttpTransport]: 🚀 HTTP server listening on http://0.0.0.0:8080/mcp

```
Your MCP server is now live, and clients can call the `greet` tool.

---

## ✨ Features

### Defining Resources

Expose data to clients using the `@Resource` annotation. `fastmcp` automatically wraps simple return types.

```dart
/// Provides the current server time.
@Resource(
  uri: 'server://time',
  mimeType: 'text/plain',
)
String getCurrentTime() => DateTime.now().toIso8601String();
```

### Defining Prompts

Create dynamic prompt templates for LLMs. Your function must return a `PromptResult`.

```dart
@Prompt(name: 'code-review')
PromptResult createCodeReviewPrompt({required String language}) {
  return PromptResult(
    description: 'A system prompt for a $language code reviewer.',
    messages: [
      Message(
        role: 'system',
        content: TextContent(
          text: 'You are an expert code reviewer for the $language language...'
        ),
      ),
    ],
  );
}
```

### Long-Running Tasks with `McpContext`

For tasks that take time, simply add `McpContext` as a parameter to your tool. `fastmcp` will inject it, giving you access to progress reporting and cancellation.

```dart
@Tool()
Future<String> longTask(McpContext context, {int steps = 10}) async {
  for (int i = 1; i <= steps; i++) {
    // Check if the client cancelled the operation
    if (context.cancellationToken.isCancelled) {
      return 'Task Cancelled!';
    }
    // Report progress back to the client
    context.onProgress(i / steps, 'Processing step $i of $steps...');
    await Future.delayed(const Duration(seconds: 1));
  }
  return 'Task Complete!';
}
```

### Custom Metadata

Add custom `_meta` fields to your tools and resources for advanced client integration.

```dart
@Tool(
  name: 'admin-tool',
  meta: const {
    'permissions': ['admin'],
    'dangerLevel': 'high',
  },
)
void performAdminAction() { /* ... */ }
```

## 🤝 Contributing

Contributions are welcome! Please feel free to open an issue or submit a pull request

## ✍️ Author

This project is maintained by [**Yash Makan**](https://github.com/yashmakan).

I am currently looking for new job opportunities and exciting projects to work on. If you are looking for a dedicated Flutter developer or have an exciting project in mind, please feel free to reach out

- **Email**: [contact@yashmakan.com](mailto:contact@yashmakan.com)
- **Website**: [yashmakan.com](https://yashmakan.com)
- **LinkedIn**: [linkedin.com/in/yashmakan](https://www.linkedin.com/in/yashmakan)
- **GitHub**: [@yashmakan](https://github.com/yashmakan)
- **Cal.com**: [@yashmakan](https://cal.com/yashmakan/30min)

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.