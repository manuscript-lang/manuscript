# Manuscript Language Support for VS Code

This extension provides basic language support for the Manuscript programming language in Visual Studio Code.

## Manuscript Language

(Users should replace this with a brief, official description of the Manuscript language if available.)

Manuscript is a [describe key characteristics, e.g., statically-typed, compiles to Go, etc.] language.

## Features

This extension currently provides:

*   **Syntax Highlighting:** For Manuscript keywords, comments, strings, numbers, operators, and other language constructs.
*   **Basic Language Server Protocol (LSP) Features:**
    *   **Keyword and Snippet Completions:** Provides auto-completion for Manuscript keywords and common code snippets (e.g., function definitions, loops).
    *   **Placeholder Hover Information:** Shows basic information for keywords when hovered over. (Full semantic hover information is pending).
    *   **Basic Folding Ranges:** Allows collapsing/expanding code blocks based on braces (`{}`), region comments (`//{region` / `//}endregion`), and block comments (`/* ... */`).
    *   **Placeholder Diagnostics:** The framework for displaying errors and warnings is in place. However, it currently uses a *dummy parser* and provides only placeholder diagnostics. Integration with the actual Manuscript parser for real-time error checking is a key next step.
    *   **Placeholder Formatting:** The extension advertises formatting capability, but actual code formatting is not yet implemented.

## Prerequisites for Full LSP Functionality (Go Language Server)

The advanced language features (diagnostics, context-aware hover/completions, go-to-definition etc.) are provided by a separate Language Server Protocol (LSP) server written in Go. The syntax highlighting and basic snippets will work without it, but for the full experience, the Go LSP server must be built and running.

**1. Go Installation:**
   Ensure you have Go installed (version 1.18 or newer recommended).

**2. Build the Manuscript LSP Server:**
   The Manuscript LSP server is located in the `lsp` directory (expected to be a sibling to this `manuscript-vscode-extension` directory). To build it:
   ```bash
   cd ../lsp  # Navigate to the lsp directory from the extension's root
   make build
   ```
   This will compile the LSP server and place the executable at `../lsp/bin/manuscript-lsp`. The VS Code extension is configured to automatically find and launch this executable.

**3. (For Developers) Running the Extension with the LSP:**
   *   Open the `manuscript-vscode-extension` folder in VS Code.
   *   Run `npm install` to install Node.js dependencies for the extension.
   *   Run `npm run compile` to compile the extension's TypeScript files (or use the VS Code build task).
   *   Ensure the Go LSP server has been built (see step 2).
   *   Press `F5` to start a debugging session for the extension. This will open a new VS Code window (Extension Development Host) where the extension is active.
   *   Open a Manuscript file (`.ms`) in the Extension Development Host window to activate the LSP features.

## Known Issues and Limitations

*   **Diagnostics are Placeholders:** Real-time error checking based on the actual Manuscript parser is not yet implemented. The current diagnostics are from a dummy parser.
*   **Limited Code Intelligence:** Hover information and completions are basic. Advanced features like go-to-definition and context-aware suggestions depend on the full integration of Manuscript's internal parsing/analysis tools into the Go LSP server.
*   **Formatting Not Implemented:** The document formatting feature is a placeholder.

## Contributing (Placeholder)

(Details on how to contribute to the development of this extension and the Go LSP server would go here.)
