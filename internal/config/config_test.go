package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultCompilerOptions(t *testing.T) {
	opts := DefaultCompilerOptions()

	if opts.OutputDir != "./build" {
		t.Errorf("Expected outputDir './build', got '%s'", opts.OutputDir)
	}

	if opts.EntryFile != "" {
		t.Errorf("Expected entryFile '', got '%s'", opts.EntryFile)
	}
}

func TestLoadConfigFromFile(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "ms.yml")

	configContent := `
outputDir: ./output
entryFile: main.ms
`

	err := os.WriteFile(configPath, []byte(configContent), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	config, err := LoadConfig(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	if config.OutputDir != "./output" {
		t.Errorf("Expected outputDir './output', got '%s'", config.OutputDir)
	}

	if config.EntryFile != "main.ms" {
		t.Errorf("Expected entryFile 'main.ms', got '%s'", config.EntryFile)
	}
}

func TestLoadConfigFromJSON(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "ms.json")

	configContent := `{
	"outputDir": "./json-output",
	"entryFile": "app.ms"
}`

	err := os.WriteFile(configPath, []byte(configContent), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	config, err := LoadConfig(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	if config.OutputDir != "./json-output" {
		t.Errorf("Expected outputDir './json-output', got '%s'", config.OutputDir)
	}

	if config.EntryFile != "app.ms" {
		t.Errorf("Expected entryFile 'app.ms', got '%s'", config.EntryFile)
	}
}

func TestLoadConfigWithEnv(t *testing.T) {
	// Set environment variables
	os.Setenv("MS_OUTPUT_DIR", "./env-output")
	os.Setenv("MS_ENTRY_FILE", "env.ms")
	defer func() {
		os.Unsetenv("MS_OUTPUT_DIR")
		os.Unsetenv("MS_ENTRY_FILE")
	}()

	tempDir := t.TempDir()
	config, err := LoadConfig(tempDir)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	if config.OutputDir != "./env-output" {
		t.Errorf("Expected outputDir './env-output', got '%s'", config.OutputDir)
	}

	if config.EntryFile != "env.ms" {
		t.Errorf("Expected entryFile 'env.ms', got '%s'", config.EntryFile)
	}
}

func TestLoadConfigEnvOverridesFile(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "ms.yml")

	configContent := `
outputDir: ./file-output
entryFile: file.ms
`

	err := os.WriteFile(configPath, []byte(configContent), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	// Set environment variables that should override file values
	os.Setenv("MS_OUTPUT_DIR", "./env-override")
	os.Setenv("MS_ENTRY_FILE", "env-override.ms")
	defer func() {
		os.Unsetenv("MS_OUTPUT_DIR")
		os.Unsetenv("MS_ENTRY_FILE")
	}()

	config, err := LoadConfig(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	if config.OutputDir != "./env-override" {
		t.Errorf("Expected outputDir './env-override', got '%s'", config.OutputDir)
	}

	if config.EntryFile != "env-override.ms" {
		t.Errorf("Expected entryFile 'env-override.ms', got '%s'", config.EntryFile)
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
	if config.OutputDir != defaultConfig.OutputDir {
		t.Errorf("Expected default outputDir '%s', got '%s'", defaultConfig.OutputDir, config.OutputDir)
	}

	if config.EntryFile != defaultConfig.EntryFile {
		t.Errorf("Expected default entryFile '%s', got '%s'", defaultConfig.EntryFile, config.EntryFile)
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
			name: "empty output dir",
			config: &CompilerOptions{
				OutputDir: "",
				EntryFile: "main.ms",
			},
			expectError: true,
		},
		{
			name: "valid custom config",
			config: &CompilerOptions{
				OutputDir: "./custom",
				EntryFile: "app.ms",
			},
			expectError: false,
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
		OutputDir: "./custom-output",
		EntryFile: "custom.ms",
	}

	base.Merge(override)

	if base.OutputDir != "./custom-output" {
		t.Errorf("Expected outputDir './custom-output', got '%s'", base.OutputDir)
	}

	if base.EntryFile != "custom.ms" {
		t.Errorf("Expected entryFile 'custom.ms', got '%s'", base.EntryFile)
	}
}

func TestConfigMergePartial(t *testing.T) {
	base := &CompilerOptions{
		OutputDir: "./base-output",
		EntryFile: "base.ms",
	}

	override := &CompilerOptions{
		OutputDir: "./override-output",
		EntryFile: "", // Empty should not override
	}

	base.Merge(override)

	if base.OutputDir != "./override-output" {
		t.Errorf("Expected outputDir './override-output', got '%s'", base.OutputDir)
	}

	if base.EntryFile != "base.ms" {
		t.Errorf("Expected entryFile 'base.ms' (unchanged), got '%s'", base.EntryFile)
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
	err = os.WriteFile(configPath, []byte("outputDir: ./test"), 0644)
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

func TestFindConfigFileYaml(t *testing.T) {
	tempDir := t.TempDir()

	// Create ms.yaml (not ms.yml)
	configPath := filepath.Join(tempDir, "ms.yaml")
	err := os.WriteFile(configPath, []byte("outputDir: ./test"), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	foundPath, err := findConfigFile(tempDir)
	if err != nil {
		t.Fatalf("Failed to find config file: %v", err)
	}

	if foundPath != configPath {
		t.Errorf("Expected config path '%s', got '%s'", configPath, foundPath)
	}
}

func TestFindConfigFileNotFound(t *testing.T) {
	tempDir := t.TempDir()

	_, err := findConfigFile(tempDir)
	if err == nil {
		t.Errorf("Expected error when config file not found, got nil")
	}
}

func TestLoadConfigInvalidYAML(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "ms.yml")

	// Invalid YAML content
	configContent := `
outputDir: ./output
entryFile: main.ms
invalid yaml: [
`

	err := os.WriteFile(configPath, []byte(configContent), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	_, err = LoadConfig(configPath)
	if err == nil {
		t.Errorf("Expected error for invalid YAML, got nil")
	}
}

func TestLoadConfigInvalidJSON(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "ms.json")

	// Invalid JSON content
	configContent := `{
	"outputDir": "./output",
	"entryFile": "main.ms",
	"invalid": 
}`

	err := os.WriteFile(configPath, []byte(configContent), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	_, err = LoadConfig(configPath)
	if err == nil {
		t.Errorf("Expected error for invalid JSON, got nil")
	}
}

func TestConfigPrecedence(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "ms.yml")

	// Create config file with specific values
	configContent := `
outputDir: ./file-output
entryFile: file.ms
`

	err := os.WriteFile(configPath, []byte(configContent), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	// Test 1: Default values only (no file, no env)
	t.Run("defaults only", func(t *testing.T) {
		emptyDir := t.TempDir()
		config, err := LoadConfig(emptyDir)
		if err != nil {
			t.Fatalf("Failed to load config: %v", err)
		}

		defaultConfig := DefaultCompilerOptions()
		if config.OutputDir != defaultConfig.OutputDir {
			t.Errorf("Expected default outputDir '%s', got '%s'", defaultConfig.OutputDir, config.OutputDir)
		}
		if config.EntryFile != defaultConfig.EntryFile {
			t.Errorf("Expected default entryFile '%s', got '%s'", defaultConfig.EntryFile, config.EntryFile)
		}
	})

	// Test 2: File values override defaults
	t.Run("file overrides defaults", func(t *testing.T) {
		config, err := LoadConfig(configPath)
		if err != nil {
			t.Fatalf("Failed to load config: %v", err)
		}

		if config.OutputDir != "./file-output" {
			t.Errorf("Expected file outputDir './file-output', got '%s'", config.OutputDir)
		}
		if config.EntryFile != "file.ms" {
			t.Errorf("Expected file entryFile 'file.ms', got '%s'", config.EntryFile)
		}
	})

	// Test 3: Environment variables override file values
	t.Run("env overrides file", func(t *testing.T) {
		os.Setenv("MS_OUTPUT_DIR", "./env-output")
		os.Setenv("MS_ENTRY_FILE", "env.ms")
		defer func() {
			os.Unsetenv("MS_OUTPUT_DIR")
			os.Unsetenv("MS_ENTRY_FILE")
		}()

		config, err := LoadConfig(configPath)
		if err != nil {
			t.Fatalf("Failed to load config: %v", err)
		}

		if config.OutputDir != "./env-output" {
			t.Errorf("Expected env outputDir './env-output', got '%s'", config.OutputDir)
		}
		if config.EntryFile != "env.ms" {
			t.Errorf("Expected env entryFile 'env.ms', got '%s'", config.EntryFile)
		}
	})

	// Test 4: Partial environment override (only one field)
	t.Run("partial env override", func(t *testing.T) {
		os.Setenv("MS_OUTPUT_DIR", "./partial-env-output")
		// Don't set MS_ENTRY_FILE - should use file value
		defer func() {
			os.Unsetenv("MS_OUTPUT_DIR")
		}()

		config, err := LoadConfig(configPath)
		if err != nil {
			t.Fatalf("Failed to load config: %v", err)
		}

		if config.OutputDir != "./partial-env-output" {
			t.Errorf("Expected env outputDir './partial-env-output', got '%s'", config.OutputDir)
		}
		if config.EntryFile != "file.ms" {
			t.Errorf("Expected file entryFile 'file.ms', got '%s'", config.EntryFile)
		}
	})

	// Test 5: Empty environment variables don't override
	t.Run("empty env doesn't override", func(t *testing.T) {
		os.Setenv("MS_OUTPUT_DIR", "")
		os.Setenv("MS_ENTRY_FILE", "")
		defer func() {
			os.Unsetenv("MS_OUTPUT_DIR")
			os.Unsetenv("MS_ENTRY_FILE")
		}()

		config, err := LoadConfig(configPath)
		if err != nil {
			t.Fatalf("Failed to load config: %v", err)
		}

		// Empty env vars should not override file values
		if config.OutputDir != "./file-output" {
			t.Errorf("Expected file outputDir './file-output', got '%s'", config.OutputDir)
		}
		if config.EntryFile != "file.ms" {
			t.Errorf("Expected file entryFile 'file.ms', got '%s'", config.EntryFile)
		}
	})
}
