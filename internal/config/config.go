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
	Sourcemap bool   `yaml:"sourcemap" json:"sourcemap"`
}

// MsConfig represents the top-level configuration structure
type MsConfig struct {
	CompilerOptions CompilerOptions `yaml:"compilerOptions" json:"compilerOptions"`
}

// DefaultConfig returns the default configuration
func DefaultConfig() *MsConfig {
	return &MsConfig{
		CompilerOptions: CompilerOptions{
			OutputDir: "./build",
			EntryFile: "",
			Sourcemap: true, // Enable sourcemaps by default
		},
	}
}

// LoadConfig loads configuration from a file path
func LoadConfig(configPath string) (*MsConfig, error) {
	if configPath == "" {
		return DefaultConfig(), nil
	}

	// If path is a directory, look for config files in it
	if stat, err := os.Stat(configPath); err == nil && stat.IsDir() {
		configPath = findConfigInDir(configPath)
		if configPath == "" {
			return DefaultConfig(), nil
		}
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file %s: %w", configPath, err)
	}

	config := &MsConfig{}
	if strings.HasSuffix(configPath, ".json") {
		err = json.Unmarshal(data, config)
	} else {
		err = yaml.Unmarshal(data, config)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to parse config file %s: %w", configPath, err)
	}

	// Apply defaults for empty fields
	if config.CompilerOptions.OutputDir == "" {
		config.CompilerOptions.OutputDir = "./build"
	}

	return config, nil
}

// findConfigInDir finds a config file in the specified directory
func findConfigInDir(dir string) string {
	configNames := []string{"ms.yml", "ms.yaml", "ms.json"}

	for _, name := range configNames {
		configPath := filepath.Join(dir, name)
		if _, err := os.Stat(configPath); err == nil {
			return configPath
		}
	}

	return ""
}
