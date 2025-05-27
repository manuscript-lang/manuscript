package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefault(t *testing.T) {
	opts := DefaultCompilerOptions()
	if opts.OutputDir != "./build" {
		t.Errorf("Expected outputDir './build', got '%s'", opts.OutputDir)
	}
	if opts.EntryFile != "" {
		t.Errorf("Expected entryFile '', got '%s'", opts.EntryFile)
	}
}

func TestLoadFromFile(t *testing.T) {
	tests := []struct {
		name     string
		filename string
		content  string
		expected *CompilerOptions
	}{
		{
			name:     "YAML config",
			filename: "ms.yml",
			content:  "outputDir: ./output\nentryFile: main.ms",
			expected: &CompilerOptions{OutputDir: "./output", EntryFile: "main.ms"},
		},
		{
			name:     "JSON config",
			filename: "ms.json",
			content:  `{"outputDir": "./json-output", "entryFile": "app.ms"}`,
			expected: &CompilerOptions{OutputDir: "./json-output", EntryFile: "app.ms"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tempDir := t.TempDir()
			configPath := filepath.Join(tempDir, tt.filename)

			err := os.WriteFile(configPath, []byte(tt.content), 0644)
			if err != nil {
				t.Fatalf("Failed to write config file: %v", err)
			}

			config, err := LoadCompilerOptions(configPath)
			if err != nil {
				t.Fatalf("Failed to load config: %v", err)
			}

			if config.OutputDir != tt.expected.OutputDir {
				t.Errorf("Expected outputDir '%s', got '%s'", tt.expected.OutputDir, config.OutputDir)
			}
			if config.EntryFile != tt.expected.EntryFile {
				t.Errorf("Expected entryFile '%s', got '%s'", tt.expected.EntryFile, config.EntryFile)
			}
		})
	}
}

func TestLoadWithEnvVar(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "custom-config.yml")
	content := "outputDir: ./env-output\nentryFile: env.ms"

	err := os.WriteFile(configPath, []byte(content), 0644)
	if err != nil {
		t.Fatalf("Failed to write config file: %v", err)
	}

	// Store original env var and restore after test
	originalEnv := os.Getenv("MS_CONFIG_FILE")
	defer func() {
		if originalEnv == "" {
			os.Unsetenv("MS_CONFIG_FILE")
		} else {
			os.Setenv("MS_CONFIG_FILE", originalEnv)
		}
	}()

	os.Setenv("MS_CONFIG_FILE", configPath)

	config, err := LoadCompilerOptions("")
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

func TestLoadNotFound(t *testing.T) {
	tempDir := t.TempDir()
	config, err := LoadCompilerOptions(tempDir)
	if err != nil {
		t.Fatalf("Load should not fail when no config file found: %v", err)
	}

	defaultConfig := DefaultCompilerOptions()
	if config.OutputDir != defaultConfig.OutputDir {
		t.Errorf("Expected default outputDir '%s', got '%s'", defaultConfig.OutputDir, config.OutputDir)
	}
	if config.EntryFile != defaultConfig.EntryFile {
		t.Errorf("Expected default entryFile '%s', got '%s'", defaultConfig.EntryFile, config.EntryFile)
	}
}

func TestFindConfigFile(t *testing.T) {
	tempDir := t.TempDir()
	subDir := filepath.Join(tempDir, "subdir")
	err := os.MkdirAll(subDir, 0755)
	if err != nil {
		t.Fatalf("Failed to create subdirectory: %v", err)
	}

	tests := []struct {
		name     string
		filename string
		content  string
	}{
		{"YAML config", "ms.yml", "outputDir: ./test"},
		{"YAML config alt", "ms.yaml", "outputDir: ./test"},
		{"JSON config", "ms.json", `{"outputDir": "./test"}`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			configPath := filepath.Join(tempDir, tt.filename)

			err := os.WriteFile(configPath, []byte(tt.content), 0644)
			if err != nil {
				t.Fatalf("Failed to write config file: %v", err)
			}
			defer os.Remove(configPath)

			foundPath := findConfig(subDir)
			if foundPath != configPath {
				t.Errorf("Expected config path '%s', got '%s'", configPath, foundPath)
			}
		})
	}

	// Test when no config file exists
	t.Run("no config file", func(t *testing.T) {
		foundPath := findConfig(subDir)
		if foundPath != "" {
			t.Errorf("Expected empty path when config file not found, got '%s'", foundPath)
		}
	})
}

func TestLoadInvalidFiles(t *testing.T) {
	tests := []struct {
		name     string
		filename string
		content  string
	}{
		{"invalid YAML", "ms.yml", "outputDir: ./output\ninvalid yaml: ["},
		{"invalid JSON", "ms.json", `{"outputDir": "./output", "invalid": }`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tempDir := t.TempDir()
			configPath := filepath.Join(tempDir, tt.filename)

			err := os.WriteFile(configPath, []byte(tt.content), 0644)
			if err != nil {
				t.Fatalf("Failed to write config file: %v", err)
			}

			_, err = LoadCompilerOptions(configPath)
			if err == nil {
				t.Errorf("Expected error for invalid %s, got nil", tt.name)
			}
		})
	}
}

func TestMerge(t *testing.T) {
	base := DefaultCompilerOptions()
	override := &CompilerOptions{OutputDir: "./custom-output", EntryFile: "custom.ms"}

	base.Merge(override)

	if base.OutputDir != "./custom-output" {
		t.Errorf("Expected outputDir './custom-output', got '%s'", base.OutputDir)
	}
	if base.EntryFile != "custom.ms" {
		t.Errorf("Expected entryFile 'custom.ms', got '%s'", base.EntryFile)
	}

	// Test partial merge (empty values don't override)
	base2 := &CompilerOptions{OutputDir: "./base", EntryFile: "base.ms"}
	override2 := &CompilerOptions{OutputDir: "./override", EntryFile: ""}

	base2.Merge(override2)

	if base2.OutputDir != "./override" {
		t.Errorf("Expected outputDir './override', got '%s'", base2.OutputDir)
	}
	if base2.EntryFile != "base.ms" {
		t.Errorf("Expected entryFile 'base.ms' (unchanged), got '%s'", base2.EntryFile)
	}
}
