package config

import (
	"path/filepath"
)

// CompilerContext holds the configuration and state for a compilation session
type CompilerContext struct {
	Config     *CompilerOptions
	WorkingDir string
	SourceFile string
	ConfigPath string
}

// NewCompilerContext creates a new compiler context with the given working directory
func NewCompilerContext(workingDir string) (*CompilerContext, error) {
	config, err := LoadConfig(workingDir)
	if err != nil {
		return nil, err
	}

	return &CompilerContext{
		Config:     config,
		WorkingDir: workingDir,
	}, nil
}

// NewCompilerContextWithConfig creates a new compiler context with the given configuration
func NewCompilerContextWithConfig(config *CompilerOptions, workingDir string) *CompilerContext {
	return &CompilerContext{
		Config:     config,
		WorkingDir: workingDir,
	}
}

// SetSourceFile sets the source file being compiled and loads any local configuration
func (ctx *CompilerContext) SetSourceFile(sourceFile string) error {
	ctx.SourceFile = sourceFile

	sourceDir := filepath.Dir(sourceFile)
	localConfig, err := LoadConfig(sourceDir)
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
