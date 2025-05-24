---
title: "Installation"
linkTitle: "Installation"
weight: 1
description: >
  Install manuscript and set up your development environment.
---

Get manuscript up and running on your system. manuscript compiles to Go, so you'll need Go installed.

## Prerequisites

- Go 1.22 or later
- Git

## Install Go

If you don't have Go installed:

### macOS
```bash
brew install go
```

### Linux
```bash
# Download and install Go from https://golang.org/dl/
wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
```

### Windows
Download and run the installer from [https://golang.org/dl/](https://golang.org/dl/)

## Install manuscript

### From Source

```bash
# Clone the repository
git clone https://github.com/manuscript-lang/manuscript.git
cd manuscript

# Build the compiler
make build-msc

# The msc binary will be in ./build/msc
```

### Add to PATH

Add the manuscript compiler to your PATH:

```bash
# macOS/Linux
echo 'export PATH=$PATH:/path/to/manuscript/build' >> ~/.bashrc
source ~/.bashrc

# Or create a symlink
sudo ln -s /path/to/manuscript/build/msc /usr/local/bin/msc
```

## Verify Installation

Test that manuscript is working:

```bash
# Check version
msc --version

# Create a test file
echo 'fn main() { print("Hello, manuscript!") }' > test.ms

# Compile and run
msc test.ms
```

You should see:
```
Hello, manuscript!
```

## Editor Support

### VS Code
- Syntax highlighting and basic language support coming soon

### Vim/Neovim
- Add `*.ms` files to your Go syntax highlighting for now

### Other Editors
- Use Go syntax highlighting as a temporary solution

## Next Steps

1. [Write your first program](../first-program/) - Hello World tutorial
2. [Learn the language overview](../overview/) - Understand manuscript's design
3. [Explore language features](../../constructs/) - Deep dive into the language

## Troubleshooting

### Go Not Found
Ensure Go is properly installed and in your PATH:
```bash
go version
```

### Build Errors
Make sure you have the latest Go version and all dependencies:
```bash
cd manuscript
go mod tidy
make clean
make build-msc
```

### Permission Errors
On Unix systems, you may need to make the binary executable:
```bash
chmod +x build/msc
``` 