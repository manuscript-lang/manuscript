package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
)

// CompilerOptions represents the configuration options for the Manuscript compiler
type CompilerOptions struct {
	Target      string   `yaml:"target" json:"target"`
	OutputDir   string   `yaml:"outputDir" json:"outputDir"`
	PackageName string   `yaml:"packageName" json:"packageName"`
	Debug       bool     `yaml:"-" json:"-"` // CLI/env only
	Strict      bool     `yaml:"strict" json:"strict"`
	Include     []string `yaml:"include" json:"include"`
	Exclude     []string `yaml:"exclude" json:"exclude"`
	ModuleName  string   `yaml:"moduleName" json:"moduleName"`
}

// DefaultCompilerOptions returns the default compiler configuration
func DefaultCompilerOptions() *CompilerOptions {
	return &CompilerOptions{
		Target:      "go",
		OutputDir:   "./build",
		PackageName: "main",
		Debug:       false,
		Strict:      false,
		Include:     []string{"**/*.ms"},
		Exclude:     []string{},
		ModuleName:  "",
	}
}

// LoadConfig loads configuration with precedence: file -> env vars
func LoadConfig(dir string) (*CompilerOptions, error) {
	config := DefaultCompilerOptions()

	// Load from file if found
	if configPath, err := findConfigFile(dir); err == nil {
		if err := loadFromFile(configPath, config); err != nil {
			return nil, err
		}
	}

	// Override with environment variables
	loadFromEnv(config)

	return config, nil
}

// LoadConfigFromPath loads configuration from a specific file path with env overrides
func LoadConfigFromPath(configPath string) (*CompilerOptions, error) {
	config := DefaultCompilerOptions()

	if err := loadFromFile(configPath, config); err != nil {
		return nil, err
	}

	loadFromEnv(config)
	return config, nil
}

// loadFromEnv loads configuration values from environment variables
func loadFromEnv(config *CompilerOptions) {
	if val := os.Getenv("MS_TARGET"); val != "" {
		config.Target = val
	}
	if val := os.Getenv("MS_OUTPUT_DIR"); val != "" {
		config.OutputDir = val
	}
	if val := os.Getenv("MS_PACKAGE_NAME"); val != "" {
		config.PackageName = val
	}
	if val := os.Getenv("MS_DEBUG"); val != "" {
		if debug, err := strconv.ParseBool(val); err == nil {
			config.Debug = debug
		}
	}
	if val := os.Getenv("MS_STRICT"); val != "" {
		if strict, err := strconv.ParseBool(val); err == nil {
			config.Strict = strict
		}
	}
	if val := os.Getenv("MS_INCLUDE"); val != "" {
		config.Include = strings.Split(val, ",")
		for i, pattern := range config.Include {
			config.Include[i] = strings.TrimSpace(pattern)
		}
	}
	if val := os.Getenv("MS_EXCLUDE"); val != "" {
		config.Exclude = strings.Split(val, ",")
		for i, pattern := range config.Exclude {
			config.Exclude[i] = strings.TrimSpace(pattern)
		}
	}
	if val := os.Getenv("MS_MODULE_NAME"); val != "" {
		config.ModuleName = val
	}
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
	switch ext {
	case ".yml", ".yaml":
		err = yaml.Unmarshal(data, config)
	case ".json":
		err = json.Unmarshal(data, config)
	default:
		err = yaml.Unmarshal(data, config)
	}

	if err != nil {
		return fmt.Errorf("failed to parse config file %s: %w", configPath, err)
	}

	return nil
}

// Merge merges another configuration into this one, with the other config taking precedence
func (c *CompilerOptions) Merge(other *CompilerOptions) {
	defaults := DefaultCompilerOptions()

	if other.Target != "" && other.Target != defaults.Target {
		c.Target = other.Target
	}
	if other.OutputDir != "" && other.OutputDir != defaults.OutputDir {
		c.OutputDir = other.OutputDir
	}
	if other.PackageName != "" && other.PackageName != defaults.PackageName {
		c.PackageName = other.PackageName
	}
	if other.Strict != defaults.Strict {
		c.Strict = other.Strict
	}
	if len(other.Include) > 0 {
		c.Include = other.Include
	}
	if len(other.Exclude) > 0 {
		c.Exclude = other.Exclude
	}
	if other.ModuleName != "" && other.ModuleName != defaults.ModuleName {
		c.ModuleName = other.ModuleName
	}
}

// Validate validates the configuration options
func (c *CompilerOptions) Validate() error {
	if c.Target == "" {
		return fmt.Errorf("target cannot be empty")
	}
	if c.PackageName == "" {
		return fmt.Errorf("packageName cannot be empty")
	}
	if c.Target != "go" {
		return fmt.Errorf("invalid target '%s', supported targets: [go]", c.Target)
	}
	return nil
}
