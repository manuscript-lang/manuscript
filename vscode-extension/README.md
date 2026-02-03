# Manuscript Language Extension for VS Code

Provides language support for Manuscript (`.ms` files).

## Features

- **Syntax highlighting** for keywords, operators, strings, numbers, comments
- **Diagnostics** - type errors and warnings displayed inline
- **Hover** - shows type information for functions and types
- **Completion** - keywords, built-in types, functions, and user-defined symbols
- **Document symbols** - outline view for functions, types, and tests

## Installation

### From VSIX

```bash
cd vscode-extension
./install.sh
```

Or manually:

```bash
cd vscode-extension
bun install
bun run build
npx @vscode/vsce package --no-dependencies -o manuscript.vsix
cursor --install-extension manuscript.vsix
```

### Development

1. Open the `vscode-extension` folder in Cursor
2. Press F5 to launch Extension Development Host
3. Open a `.ms` file to test

## Supported Language Features

### Syntax Highlighting

- Keywords: `fn`, `type`, `let`, `var`, `if`, `else`, `for`, `match`, etc.
- Operators: `+`, `-`, `*`, `/`, `==`, `!=`, `=>`, `|>`, `..`, `...`
- Strings: regular `"..."`, multiline `"""..."""`, raw `r"..."`, byte `b"..."`
- String interpolation: `{expr}` inside strings
- Numbers: decimal, hex `0x`, binary `0b`, scientific notation
- Comments: `// single line`

### LSP Features

- Real-time type checking with error diagnostics
- Hover shows function signatures and type info
- Completion for keywords, types, and identifiers
- Document outline for navigation
