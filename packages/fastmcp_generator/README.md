
# FastMCP Generator ⚙️

[![Pub Version](https://img.shields.io/pub/v/fastmcp_generator?style=for-the-badge&logo=dart&logoColor=white)](https://pub.dev/packages/fastmcp_generator)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

**The build-time code generator for the [fastmcp](https://pub.dev/packages/fastmcp) framework.**

This package contains the `build_runner` logic that enables the declarative, annotation-based API of `fastmcp`. It inspects your code for `@Tool`, `@Resource`, and `@Prompt` annotations and generates the necessary boilerplate to connect your functions to the MCP engine.

**Note:** You do not need to use this package directly. It is intended to be used as a `dev_dependency` and run via `build_runner`.

## Features

*   **Annotation Processing:** Scans your project for `@Tool`, `@Resource`, and `@Prompt` annotations.
*   **Schema Inference:** Automatically generates JSON schemas for tool and prompt arguments by analyzing function parameter types, names, and nullability.
*   **Handler Generation:** Creates the wrapper functions that:
    *   Safely parse and type-cast incoming JSON-RPC arguments.
    *   Handle required, optional, and default-value parameters.
    *   Inject the `McpContext` for advanced use cases.
    *   Intelligently wrap return values into the correct MCP `Result` objects.
    *   Include `try-catch` blocks for robust error handling.
*   **Metadata Parsing:** Reads doc comments (`///`) and `@Param` annotations to generate rich descriptions for your protocol schemas. It also processes `const` maps in `meta` properties.

## 📚 Table of Contents

-   [🚀 Installation](#-installation)
-   [🏃 Usage](#-usage)
-   [🛠️ What It Generates](#️-what-it-generates)
-   [🤝 Contributing](#-contributing)
-   [✍️ Author](#️-author)
-   [📜 License](#-license)

## 🚀 Installation

Add `fastmcp_generator` and `build_runner` to your `dev_dependencies` in `pubspec.yaml`.

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  fastmcp_generator: ^0.1.0
```

## 🏃 Usage

This generator is designed to be used with the `build_runner` command.

1.  **Annotate your functions** in your project using the annotations from the `fastmcp` package.
2.  **Add the `part` directive** at the top of your file: `part 'your_file.fastmcp.g.dart';`
3.  **Run the builder:**

```bash
dart run build_runner build --delete-conflicting-outputs
```

This will generate the necessary part file containing the `registerGenerated` function.

## 🛠️ What It Generates

Given a simple annotated function:

```dart
/// Adds two numbers together.
@Tool()
int add({required int a, required int b}) => a + b;
```

The generator produces the following registration code (simplified for clarity):

```dart
// In your_file.fastmcp.g.dart
void registerGenerated(FastMCP app) {
  app.registerToolInternal(
    tool: Tool(
      name: 'add',
      description: 'Adds two numbers together.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'a': {'type': 'number', ...},
          'b': {'type': 'number', ...},
        },
        'required': ['a', 'b'],
      },
    ),
    handler: (args, context) async {
      try {
        // Safe argument parsing
        final a = (args['a'] as num).toInt();
        final b = (args['b'] as num).toInt();
        // Function call and result wrapping
        final result = add(a: a, b: b);
        return ToolResultWrapper.wrap(result);
      } catch (e, s) {
        // Error handling
        return CallToolResult(isError: true, ...);
      }
    },
  );
}
```

## 🤝 Contributing

Contributions to the generator are highly welcome, especially for improving schema inference, supporting more complex types, or enhancing performance. Please open an issue to discuss your ideas on the [main repository](https://github.com/yashmakan/fastmcp).

## ✍️ Author

This project is maintained by [**Yash Makan**](https://github.com/yashmakan).

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.