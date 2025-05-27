package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefault(t *testing.T) {
	cfg := DefaultConfig()
	if cfg.CompilerOptions.OutputDir != "./build" {
		t.Errorf("Expected outputDir './build', got '%s'", cfg.CompilerOptions.OutputDir)
	}
	if cfg.CompilerOptions.EntryFile != "" {
		t.Errorf("Expected entryFile '', got '%s'", cfg.CompilerOptions.EntryFile)
	}
}

func TestLoadFromFile(t *testing.T) {
	tests := []struct {
		name     string
		filename string
		content  string
		expected *MsConfig
	}{
		{
			name:     "YAML config",
			filename: "ms.yml",
			content:  "compilerOptions:\n  outputDir: ./output\n  entryFile: main.ms",
			expected: &MsConfig{CompilerOptions: CompilerOptions{OutputDir: "./output", EntryFile: "main.ms"}},
		},
		{
			name:     "JSON config",
			filename: "ms.json",
			content:  `{"compilerOptions": {"outputDir": "./json-output", "entryFile": "app.ms"}}`,
			expected: &MsConfig{CompilerOptions: CompilerOptions{OutputDir: "./json-output", EntryFile: "app.ms"}},
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

			config, err := LoadConfig(configPath)
			if err != nil {
				t.Fatalf("Failed to load config: %v", err)
			}

			if config.CompilerOptions.OutputDir != tt.expected.CompilerOptions.OutputDir {
				t.Errorf("Expected outputDir '%s', got '%s'", tt.expected.CompilerOptions.OutputDir, config.CompilerOptions.OutputDir)
			}
			if config.CompilerOptions.EntryFile != tt.expected.CompilerOptions.EntryFile {
				t.Errorf("Expected entryFile '%s', got '%s'", tt.expected.CompilerOptions.EntryFile, config.CompilerOptions.EntryFile)
			}
		})
	}
}

func TestLoadNotFound(t *testing.T) {
	tempDir := t.TempDir()
	config, err := LoadConfig(tempDir)
	if err != nil {
		t.Fatalf("Load should not fail when no config file found: %v", err)
	}

	defaultConfig := DefaultConfig()
	if config.CompilerOptions.OutputDir != defaultConfig.CompilerOptions.OutputDir {
		t.Errorf("Expected default outputDir '%s', got '%s'", defaultConfig.CompilerOptions.OutputDir, config.CompilerOptions.OutputDir)
	}
	if config.CompilerOptions.EntryFile != defaultConfig.CompilerOptions.EntryFile {
		t.Errorf("Expected default entryFile '%s', got '%s'", defaultConfig.CompilerOptions.EntryFile, config.CompilerOptions.EntryFile)
	}
}

func TestFindConfigFile(t *testing.T) {
	tests := []struct {
		name     string
		filename string
		content  string
	}{
		{
			name:     "YAML config",
			filename: "ms.yml",
			content:  "compilerOptions:\n  outputDir: ./output\n  entryFile: main.ms",
		},
		{
			name:     "YAML config alt",
			filename: "ms.yaml",
			content:  "compilerOptions:\n  outputDir: ./output\n  entryFile: main.ms",
		},
		{
			name:     "JSON config",
			filename: "ms.json",
			content:  `{"compilerOptions": {"outputDir": "./json-output", "entryFile": "app.ms"}}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tempDir := t.TempDir()
			subDir := filepath.Join(tempDir, "subdir")
			err := os.MkdirAll(subDir, 0755)
			if err != nil {
				t.Fatalf("Failed to create subdirectory: %v", err)
			}

			configPath := filepath.Join(tempDir, tt.filename)
			err = os.WriteFile(configPath, []byte(tt.content), 0644)
			if err != nil {
				t.Fatalf("Failed to write config file: %v", err)
			}

			foundPath := findConfigInDir(tempDir)
			if foundPath == "" {
				t.Errorf("Expected to find config file, but got empty path")
			}
			if foundPath != configPath {
				t.Errorf("Expected config path '%s', got '%s'", configPath, foundPath)
			}
		})
	}

	t.Run("no config file", func(t *testing.T) {
		tempDir := t.TempDir()
		foundPath := findConfigInDir(tempDir)
		if foundPath != "" {
			t.Errorf("Expected empty path when no config file exists, got '%s'", foundPath)
		}
	})
}

func TestLoadInvalidFiles(t *testing.T) {
	tests := []struct {
		name     string
		filename string
		content  string
	}{
		{
			name:     "invalid YAML",
			filename: "ms.yml",
			content:  "invalid: yaml: content: [",
		},
		{
			name:     "invalid JSON",
			filename: "ms.json",
			content:  `{"invalid": json}`,
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

			_, err = LoadConfig(configPath)
			if err == nil {
				t.Error("Expected error when loading invalid config file")
			}
		})
	}
}
