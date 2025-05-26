package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultCompilerOptions(t *testing.T) {
	opts := DefaultCompilerOptions()

	if opts.Target != "go" {
		t.Errorf("Expected target 'go', got '%s'", opts.Target)
	}

	if opts.PackageName != "main" {
		t.Errorf("Expected packageName 'main', got '%s'", opts.PackageName)
	}

	if opts.Debug != false {
		t.Errorf("Expected debug false, got %v", opts.Debug)
	}
}

func TestLoadConfigFromFile(t *testing.T) {
	// Create a temporary config file
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "ms.yml")

	configContent := `
target: go
packageName: test
strict: false
outputDir: ./output
include:
  - "**/*.ms"
exclude:
  - "**/test/**"
moduleName: "test-module"
`

	err := os.WriteFile(configPath, []byte(configContent), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	config, err := LoadConfigFromPath(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	if config.Target != "go" {
		t.Errorf("Expected target 'go', got '%s'", config.Target)
	}

	if config.PackageName != "test" {
		t.Errorf("Expected packageName 'test', got '%s'", config.PackageName)
	}

	if config.OutputDir != "./output" {
		t.Errorf("Expected outputDir './output', got '%s'", config.OutputDir)
	}

	if config.ModuleName != "test-module" {
		t.Errorf("Expected moduleName 'test-module', got '%s'", config.ModuleName)
	}
}

func TestLoadConfigWithEnv(t *testing.T) {
	// Set environment variables
	os.Setenv("MS_PACKAGE_NAME", "envtest")
	os.Setenv("MS_DEBUG", "true")
	os.Setenv("MS_STRICT", "true")
	defer func() {
		os.Unsetenv("MS_PACKAGE_NAME")
		os.Unsetenv("MS_DEBUG")
		os.Unsetenv("MS_STRICT")
	}()

	tempDir := t.TempDir()
	config, err := LoadConfig(tempDir)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	if config.PackageName != "envtest" {
		t.Errorf("Expected packageName 'envtest', got '%s'", config.PackageName)
	}

	if config.Debug != true {
		t.Errorf("Expected debug true, got %v", config.Debug)
	}

	if config.Strict != true {
		t.Errorf("Expected strict true, got %v", config.Strict)
	}
}

func TestLoadConfigNotFound(t *testing.T) {
	tempDir := t.TempDir()

	config, err := LoadConfig(tempDir)
	if err != nil {
		t.Fatalf("LoadConfig should not fail when no config file found: %v", err)
	}

	// Should return default config
	defaultConfig := DefaultCompilerOptions()
	if config.Target != defaultConfig.Target {
		t.Errorf("Expected default target, got '%s'", config.Target)
	}
}

func TestConfigValidation(t *testing.T) {
	tests := []struct {
		name        string
		config      *CompilerOptions
		expectError bool
	}{
		{
			name:        "valid config",
			config:      DefaultCompilerOptions(),
			expectError: false,
		},
		{
			name: "empty target",
			config: &CompilerOptions{
				Target:      "",
				PackageName: "main",
			},
			expectError: true,
		},
		{
			name: "empty package name",
			config: &CompilerOptions{
				Target:      "go",
				PackageName: "",
			},
			expectError: true,
		},
		{
			name: "invalid target",
			config: &CompilerOptions{
				Target:      "invalid",
				PackageName: "main",
			},
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.Validate()
			if tt.expectError && err == nil {
				t.Errorf("Expected validation error, got nil")
			}
			if !tt.expectError && err != nil {
				t.Errorf("Expected no validation error, got: %v", err)
			}
		})
	}
}

func TestConfigMerge(t *testing.T) {
	base := DefaultCompilerOptions()
	override := &CompilerOptions{
		Target:      "go",
		PackageName: "custom",
		Strict:      true,
		OutputDir:   "./custom-output",
	}

	base.Merge(override)

	if base.PackageName != "custom" {
		t.Errorf("Expected packageName 'custom', got '%s'", base.PackageName)
	}

	if base.Strict != true {
		t.Errorf("Expected strict true, got %v", base.Strict)
	}

	if base.OutputDir != "./custom-output" {
		t.Errorf("Expected outputDir './custom-output', got '%s'", base.OutputDir)
	}

	// Target should remain the same since it's the same as default
	if base.Target != "go" {
		t.Errorf("Expected target 'go', got '%s'", base.Target)
	}
}

func TestFindConfigFile(t *testing.T) {
	// Create a temporary directory structure
	tempDir := t.TempDir()
	subDir := filepath.Join(tempDir, "subdir")
	err := os.MkdirAll(subDir, 0755)
	if err != nil {
		t.Fatalf("Failed to create subdirectory: %v", err)
	}

	// Create config file in parent directory
	configPath := filepath.Join(tempDir, "ms.yml")
	err = os.WriteFile(configPath, []byte("target: go"), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	// Search from subdirectory should find parent config
	foundPath, err := findConfigFile(subDir)
	if err != nil {
		t.Fatalf("Failed to find config file: %v", err)
	}

	if foundPath != configPath {
		t.Errorf("Expected config path '%s', got '%s'", configPath, foundPath)
	}
}
