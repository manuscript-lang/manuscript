---
title: "Downloads"
linkTitle: "Downloads"
weight: 20
---

# Download Manuscript

Get the latest version of the Manuscript programming language.

## Latest Release

### Version 0.1.0 (Development)

Currently, Manuscript is in active development. You can build from source:

```bash
# Clone the repository
git clone https://github.com/manuscript-lang/manuscript.git
cd manuscript

# Build the compiler
make build-msc

# The compiler will be available at ./build/msc
```

## Installation Methods

### From Source

**Prerequisites:**
- Go 1.19 or later
- Git

**Steps:**

1. Clone the repository:
   ```bash
   git clone https://github.com/manuscript-lang/manuscript.git
   cd manuscript
   ```

2. Build the compiler:
   ```bash
   make build-msc
   ```

3. Add to your PATH (optional):
   ```bash
   export PATH=$PATH:$(pwd)/build
   ```

### Development Tools

#### Language Server

Build the language server for IDE support:

```bash
make build-lsp
```

#### VS Code Extension

Build and install the VS Code extension:

```bash
make build-vscode-extension
```

## Verify Installation

Test your installation by creating a simple program:

```bash
# Create a test file
echo 'print("Hello, Manuscript!")' > test.ms

# Run it
./build/msc test.ms
```

## Release Notes

### v0.1.0 (Development)
- Initial compiler implementation
- Basic language constructs
- Language server support
- VS Code extension

## System Requirements

- **Operating Systems**: Linux, macOS, Windows
- **Memory**: 512MB RAM minimum
- **Storage**: 100MB available space
- **Dependencies**: None (statically linked binary) 