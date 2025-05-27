package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// CompilerOptions represents the configuration options for the Manuscript compiler
type CompilerOptions struct {
	OutputDir string `yaml:"outputDir" json:"outputDir"`
	EntryFile string `yaml:"entryFile" json:"entryFile"`
}

// DefaultCompilerOptions returns the default compiler configuration
func DefaultCompilerOptions() *CompilerOptions {
	return &CompilerOptions{
		OutputDir: "./build",
		EntryFile: "",
	}
}

// LoadCompilerOptions loads configuration from file, with optional config path from env var
func LoadCompilerOptions(path string) (*CompilerOptions, error) {
	if envPath := os.Getenv("MS_CONFIG_FILE"); envPath != "" {
		path = envPath
	}
	if path == "" {
		path = "."
	}

	configPath := findConfig(path)
	if configPath == "" {
		return DefaultCompilerOptions(), nil
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file %s: %w", configPath, err)
	}

	config := &CompilerOptions{}
	if strings.HasSuffix(configPath, ".json") {
		err = json.Unmarshal(data, config)
	} else {
		err = yaml.Unmarshal(data, config)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to parse config file %s: %w", configPath, err)
	}

	// Apply defaults for empty fields
	if config.OutputDir == "" {
		config.OutputDir = "./build"
	}

	return config, nil
}

// findConfig finds the config file path, returns empty string if not found
func findConfig(path string) string {
	if stat, err := os.Stat(path); err == nil && !stat.IsDir() {
		return path
	}

	dir, err := filepath.Abs(path)
	if err != nil {
		return ""
	}

	for {
		for _, name := range []string{"ms.yml", "ms.yaml", "ms.json"} {
			configPath := filepath.Join(dir, name)
			if _, err := os.Stat(configPath); err == nil {
				return configPath
			}
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	return ""
}

// Merge merges another configuration into this one, with the other config taking precedence
func (c *CompilerOptions) Merge(other *CompilerOptions) {
	if other.OutputDir != "" {
		c.OutputDir = other.OutputDir
	}
	if other.EntryFile != "" {
		c.EntryFile = other.EntryFile
	}
}
