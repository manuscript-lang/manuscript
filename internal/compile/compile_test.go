package compile

import (
	"strings"
	"testing"

	"manuscript-lang/manuscript/internal/config"
)

func TestFileSystemResolver(t *testing.T) {
	resolver := &config.FileSystemResolver{}

	// Test reading a non-existent file
	_, err := resolver.ResolveModule("non-existent-file.ms")
	if err == nil {
		t.Error("Expected error when reading non-existent file")
	}
}

func TestStringResolver(t *testing.T) {
	modules := map[string]string{
		"main.ms":  "let x = 42",
		"utils.ms": "fn add(a, b) { a + b }",
	}

	resolver := config.NewStringResolver(modules)

	// Test resolving existing module
	content, err := resolver.ResolveModule("main.ms")
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}
	if content != "let x = 42" {
		t.Errorf("Expected 'let x = 42', got: %s", content)
	}
}

func TestCompileManuscriptWithResolver(t *testing.T) {
	modules := map[string]string{
		"test.ms": "let greeting = \"Hello, World!\"",
	}
	resolver := config.NewStringResolver(modules)

	// Create a context with default config and set the resolver
	ctx := createTestContext(t)
	ctx.SourceFile = "test.ms"
	ctx.ModuleResolver = resolver

	// Get the manuscript code from the resolver
	msCode, err := resolver.ResolveModule("test.ms")
	if err != nil {
		t.Fatalf("Failed to resolve module: %v", err)
	}

	goCode, err := CompileManuscriptFromString(msCode, ctx)
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}

	if !strings.Contains(goCode, "package main") {
		t.Error("Expected Go code to contain 'package main'")
	}

	if !strings.Contains(goCode, "greeting := \"Hello, World!\"") {
		t.Error("Expected Go code to contain greeting assignment")
	}
}

func TestCompileManuscriptWithResolverError(t *testing.T) {
	modules := map[string]string{
		"other.ms": "let x = 1",
	}
	resolver := config.NewStringResolver(modules)

	// Create a context with default config and set the resolver
	ctx := createTestContext(t)
	ctx.SourceFile = "missing.ms" // File not in resolver
	ctx.ModuleResolver = resolver

	// Try to get the manuscript code from the resolver - this should fail
	_, err := resolver.ResolveModule("missing.ms")
	if err == nil {
		t.Error("Expected error when file not found in resolver")
	}

	if !strings.Contains(err.Error(), "module not found") {
		t.Errorf("Expected 'module not found' error, got: %v", err)
	}
}

func createTestContext(t *testing.T) *config.CompilerContext {
	cfg := &config.MsConfig{
		CompilerOptions: config.CompilerOptions{
			OutputDir: "./build",
			EntryFile: "",
		},
	}

	ctx, err := config.NewCompilerContext(cfg, ".", "test.ms")
	if err != nil {
		t.Fatalf("Failed to create test context: %v", err)
	}

	return ctx
}
