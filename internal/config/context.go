package config

import (
	"fmt"
	"os"
	"path/filepath"
)

// ModuleResolver interface for resolving module content by filename
type ModuleResolver interface {
	ResolveModule(filename string) (string, error)
}

// FileSystemResolver implements ModuleResolver using the file system
type FileSystemResolver struct{}

func (r *FileSystemResolver) ResolveModule(filename string) (string, error) {
	content, err := os.ReadFile(filename)
	if err != nil {
		return "", fmt.Errorf("failed to read file %s: %v", filename, err)
	}
	return string(content), nil
}

// StringResolver implements ModuleResolver using a map of filename to content
type StringResolver struct {
	modules map[string]string
}

func NewStringResolver(modules map[string]string) *StringResolver {
	return &StringResolver{modules: modules}
}

func (r *StringResolver) ResolveModule(filename string) (string, error) {
	content, ok := r.modules[filename]
	if !ok {
		return "", fmt.Errorf("module not found: %s", filename)
	}
	return content, nil
}

// CompilerContext holds the configuration and state for a compilation session
type CompilerContext struct {
	Config         *CompilerOptions
	WorkingDir     string
	SourceFile     string
	ConfigPath     string
	Debug          bool // Debug flag for enabling token dumping and other debug features
	ModuleResolver ModuleResolver
}

// NewCompilerContext creates a new compiler context with the given working directory and source file
func NewCompilerContext(workingDir, sourceFile string) (*CompilerContext, error) {
	absSourceFile, err := filepath.Abs(sourceFile)
	if err != nil {
		return nil, err
	}

	config, err := LoadCompilerOptions(workingDir)
	if err != nil {
		return nil, err
	}

	ctx := &CompilerContext{
		Config:         config,
		WorkingDir:     workingDir,
		SourceFile:     absSourceFile,
		ModuleResolver: &FileSystemResolver{},
	}

	// Load local configuration from source file directory
	sourceDir := filepath.Dir(absSourceFile)
	localConfig, err := LoadCompilerOptions(sourceDir)
	if err == nil {
		ctx.Config.Merge(localConfig)
	}

	return ctx, nil
}

// NewCompilerContextWithConfig creates a new compiler context with the given configuration and source file
func NewCompilerContextWithConfig(config *CompilerOptions, workingDir, sourceFile string) (*CompilerContext, error) {
	absSourceFile, err := filepath.Abs(sourceFile)
	if err != nil {
		return nil, err
	}

	ctx := &CompilerContext{
		Config:         config,
		WorkingDir:     workingDir,
		SourceFile:     absSourceFile,
		ModuleResolver: &FileSystemResolver{},
	}

	// Load local configuration from source file directory
	sourceDir := filepath.Dir(absSourceFile)
	localConfig, err := LoadCompilerOptions(sourceDir)
	if err == nil {
		ctx.Config.Merge(localConfig)
	}

	return ctx, nil
}

// NewCompilerContextWithResolver creates a new compiler context with a custom module resolver
func NewCompilerContextWithResolver(workingDir, sourceFile string, resolver ModuleResolver) (*CompilerContext, error) {
	absSourceFile, err := filepath.Abs(sourceFile)
	if err != nil {
		return nil, err
	}

	config, err := LoadCompilerOptions(workingDir)
	if err != nil {
		return nil, err
	}

	ctx := &CompilerContext{
		Config:         config,
		WorkingDir:     workingDir,
		SourceFile:     absSourceFile,
		ModuleResolver: resolver,
	}

	// Load local configuration from source file directory
	sourceDir := filepath.Dir(absSourceFile)
	localConfig, err := LoadCompilerOptions(sourceDir)
	if err == nil {
		ctx.Config.Merge(localConfig)
	}

	return ctx, nil
}

// SetSourceFile sets the source file being compiled and loads any local configuration
func (ctx *CompilerContext) SetSourceFile(sourceFile string) error {
	absSourceFile, err := filepath.Abs(sourceFile)
	if err != nil {
		return err
	}

	ctx.SourceFile = absSourceFile

	sourceDir := filepath.Dir(absSourceFile)
	localConfig, err := LoadCompilerOptions(sourceDir)
	if err != nil {
		return nil
	}

	ctx.Config.Merge(localConfig)
	return nil
}

// GetOutputPath returns the output path for the compiled file
func (ctx *CompilerContext) GetOutputPath() string {
	if ctx.SourceFile == "" {
		return ctx.Config.OutputDir
	}

	relPath, err := filepath.Rel(ctx.WorkingDir, ctx.SourceFile)
	if err != nil {
		relPath = filepath.Base(ctx.SourceFile)
	}

	outputFile := changeExtension(relPath, ".go")
	return filepath.Join(ctx.Config.OutputDir, outputFile)
}

// changeExtension changes the file extension
func changeExtension(filename, newExt string) string {
	ext := filepath.Ext(filename)
	if ext == "" {
		return filename + newExt
	}
	return filename[:len(filename)-len(ext)] + newExt
}

// NewCompilerContextFromFile creates a new compiler context from a source file
// If workingDir is empty, it defaults to the directory containing the source file
// If configPath is empty, it searches for config files starting from the source file directory
func NewCompilerContextFromFile(sourceFile, workingDir, configPath string) (*CompilerContext, error) {
	absSourceFile, err := filepath.Abs(sourceFile)
	if err != nil {
		return nil, err
	}

	// Default working directory to source file directory if not specified
	if workingDir == "" {
		workingDir = filepath.Dir(absSourceFile)
	}

	var config *CompilerOptions
	if configPath != "" {
		// Load specific config file
		fullConfig, err := LoadCompilerOptions(configPath)
		if err != nil {
			return nil, err
		}
		config = fullConfig
	} else {
		// Search for config starting from source file directory
		sourceDir := filepath.Dir(absSourceFile)
		fullConfig, err := LoadCompilerOptions(sourceDir)
		if err != nil {
			// Fall back to default config if no config file found
			config = DefaultCompilerOptions()
		} else {
			config = fullConfig
		}
	}

	ctx := &CompilerContext{
		Config:         config,
		WorkingDir:     workingDir,
		SourceFile:     absSourceFile,
		ConfigPath:     configPath,
		ModuleResolver: &FileSystemResolver{},
	}

	// Load local configuration from source file directory if different from config location
	sourceDir := filepath.Dir(absSourceFile)
	if configPath == "" || filepath.Dir(configPath) != sourceDir {
		localConfig, err := LoadCompilerOptions(sourceDir)
		if err == nil {
			ctx.Config.Merge(localConfig)
		}
	}

	return ctx, nil
}
