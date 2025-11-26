

## 0.1.13

- version bump to 0.1.13

## 0.1.12

- version bump to 0.1.12

## 0.1.11

- version bump to 0.1.11

## 0.1.10

- version bump to 0.1.10

## 0.1.8

- version bump to 0.1.8

## 0.1.7

- version bump to 0.1.7

## 0.1.6

- version bump to 0.1.6

## 0.1.5

- version bump to 0.1.5

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