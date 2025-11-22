## 0.1.4

- version bump to 0.1.4

## 0.1.3

- version bump to 0.1.3

## 0.1.2

- version bump to 0.1.2

## 0.1.1

- No change in FastMCP Generator

## 0.1.0

* **Initial Release**
*   **Declarative Code Generation:** Implements the core build runner logic to generate MCP server handlers from Dart annotations.
*   **Tool Support (`@Tool`):** Automatically creates `tools/call` handlers with schema inference, type-safe argument parsing, and smart result wrapping.
*   **Resource Support (`@Resource`):** Generates handlers for `resources/read` and supports declarative caching via the `cacheDuration` property.
*   **Prompt Support (`@Prompt`):** Creates `prompts/get` handlers and automatically generates the prompt's argument schema from function parameters.
*   **Context Injection:** Enables advanced tool functionality by automatically injecting an `McpContext` object for progress reporting and cancellation.
*   **Metadata Support:** Correctly parses doc comments and the `@Param` annotation for descriptions, and supports a `meta` property on annotations for custom protocol metadata.