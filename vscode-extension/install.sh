#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Installing dependencies..."
bun install

echo "Building extension..."
bun run build

echo "Packaging extension..."
npx @vscode/vsce package --no-dependencies -o manuscript.vsix

echo "Installing extension to Cursor..."
cursor --install-extension manuscript.vsix --force

echo ""
echo "Extension installed! Restart Cursor to activate."
echo "Open a .ms file to see syntax highlighting and LSP features."
