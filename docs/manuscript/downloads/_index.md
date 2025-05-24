---
title: "Downloads"
linkTitle: "Downloads"

---

Get the manuscript programming language compiler and tools for your platform.

## Latest Release

### manuscript v0.1.0 (Alpha)

The manuscript language is currently in alpha development. 

**Recommended Installation**: Build from source for the latest features and fixes.

## Build from Source

### Requirements
- Go 1.22 or later
- Git
- Make

### Installation Steps

```bash
# Clone the repository
git clone https://github.com/manuscript-lang/manuscript.git
cd manuscript

# Build the compiler
make build-msc

# The msc binary will be in ./build/msc
```

### Add to PATH

```bash
# Add to your shell profile (.bashrc, .zshrc, etc.)
export PATH=$PATH:/path/to/manuscript/build

# Or create a symlink
sudo ln -s /path/to/manuscript/build/msc /usr/local/bin/msc
```

### Verify Installation

```bash
# Check version
msc --version

# Create and run a test program
echo 'fn main() { print("Hello, manuscript!") }' > test.ms
msc test.ms
```

## Platform Support

manuscript currently supports:

- **Linux** (x86_64, ARM64)
- **macOS** (Intel, Apple Silicon)  
- **Windows** (x86_64)

The compiler produces Go source code, which can then be compiled for any platform Go supports.

## Development Builds

For the latest development features:

```bash
# Clone and switch to development branch
git clone https://github.com/manuscript-lang/manuscript.git
cd manuscript
git checkout develop

# Build development version
make build-msc
```

**Note**: Development builds may be unstable. Use the main branch for production work.

## Docker Image

Run manuscript in a container:

```bash
# Pull the latest image
docker pull manuscriptlang/manuscript:latest

# Run a manuscript file
docker run -v $(pwd):/workspace manuscriptlang/manuscript:latest msc /workspace/program.ms
```

## Editor Support

### VS Code
Syntax highlighting and language support coming soon.

### Vim/Neovim
Use Go syntax highlighting as a temporary solution:

```vim
" Add to your .vimrc
autocmd BufNewFile,BufRead *.ms set syntax=go
```

## Package Managers

Package manager support is planned for future releases:

- Homebrew (macOS/Linux)
- Chocolatey (Windows)  
- Snap (Linux)
- APT/YUM packages

## Getting Started

After installation:

1. [Write your first program](../docs/getting-started/first-program/)
2. [Learn the language overview](../docs/getting-started/overview/)
3. [Explore language features](../docs/constructs/)

## Support

If you encounter installation issues:

- Check the [installation guide](../docs/getting-started/installation/)
- Search [GitHub issues](https://github.com/manuscript-lang/manuscript/issues)
- Ask for help in [GitHub Discussions](https://github.com/manuscript-lang/manuscript/discussions) 