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
	Config         *MsConfig
	WorkingDir     string
	SourceFile     string
	Debug          bool
	ModuleResolver ModuleResolver
}

// NewCompilerContext creates a new compiler context with the given configuration and source file
func NewCompilerContext(config *MsConfig, workingDir, sourceFile string) (*CompilerContext, error) {
	absSourceFile, err := filepath.Abs(sourceFile)
	if err != nil {
		return nil, err
	}

	if workingDir == "" {
		workingDir = filepath.Dir(absSourceFile)
	}

	return &CompilerContext{
		Config:         config,
		WorkingDir:     workingDir,
		SourceFile:     absSourceFile,
		ModuleResolver: &FileSystemResolver{},
	}, nil
}

// GetOutputPath returns the output path for the compiled file
func (ctx *CompilerContext) GetOutputPath() string {
	if ctx.SourceFile == "" {
		return ctx.Config.CompilerOptions.OutputDir
	}

	relPath, err := filepath.Rel(ctx.WorkingDir, ctx.SourceFile)
	if err != nil {
		relPath = filepath.Base(ctx.SourceFile)
	}

	outputFile := changeExtension(relPath, ".go")
	return filepath.Join(ctx.Config.CompilerOptions.OutputDir, outputFile)
}

// changeExtension changes the file extension
func changeExtension(filename, newExt string) string {
	ext := filepath.Ext(filename)
	if ext == "" {
		return filename + newExt
	}
	return filename[:len(filename)-len(ext)] + newExt
}
