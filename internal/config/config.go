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

// LoadConfig loads configuration with precedence: file -> env vars
func LoadConfig(path string) (*CompilerOptions, error) {
	config := DefaultCompilerOptions()

	if path == "" {
		path = "."
	}

	stat, err := os.Stat(path)
	if err == nil {
		if stat.IsDir() {
			if configPath, err := findConfigFile(path); err == nil {
				path = configPath
			} else {
				path = ""
			}
		}
	} else {
		path = ""
	}

	if path != "" {
		if err := loadFromFile(path, config); err != nil {
			return nil, err
		}
	}

	loadFromEnv(config)
	return config, nil
}

// loadFromEnv loads configuration values from environment variables
func loadFromEnv(config *CompilerOptions) {
	if val := os.Getenv("MS_OUTPUT_DIR"); val != "" {
		config.OutputDir = val
	}
	if val := os.Getenv("MS_ENTRY_FILE"); val != "" {
		config.EntryFile = val
	}
}

func splitAndTrim(s string) []string {
	parts := strings.Split(s, ",")
	for i, part := range parts {
		parts[i] = strings.TrimSpace(part)
	}
	return parts
}

// findConfigFile searches for ms.yml starting from the given directory and walking up
func findConfigFile(startDir string) (string, error) {
	dir, err := filepath.Abs(startDir)
	if err != nil {
		return "", err
	}

	for {
		for _, name := range []string{"ms.yml", "ms.yaml"} {
			configPath := filepath.Join(dir, name)
			if _, err := os.Stat(configPath); err == nil {
				return configPath, nil
			}
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	return "", fmt.Errorf("no ms.yml or ms.yaml file found")
}

// loadFromFile loads and parses the configuration file
func loadFromFile(configPath string, config *CompilerOptions) error {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("failed to read config file %s: %w", configPath, err)
	}

	ext := strings.ToLower(filepath.Ext(configPath))
	if ext == ".json" {
		err = json.Unmarshal(data, config)
	} else {
		err = yaml.Unmarshal(data, config)
	}

	if err != nil {
		return fmt.Errorf("failed to parse config file %s: %w", configPath, err)
	}

	return nil
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

// Validate validates the configuration options
func (c *CompilerOptions) Validate() error {
	if c.OutputDir == "" {
		return fmt.Errorf("outputDir cannot be empty")
	}
	return nil
}
