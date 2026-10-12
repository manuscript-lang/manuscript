package compiler

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/project"
	"github.com/manuscript-lang/manuscript/syntax"
)

// Project is retained for callers of compiler.ReadProject.
type Project = project.Project

// ReadProject reads a manifest without parsing or generating code.
func ReadProject(filename string) (Project, error) { return project.ReadProject(filename) }

func CompileFile(filename string, options Options) Result {
	absolute, err := filepath.Abs(filename)
	if err != nil {
		return loadError(filename, err)
	}
	config := project.Project{Root: filepath.Dir(absolute), Entry: absolute, Aliases: map[string]string{}}
	if filepath.Base(absolute) == "ms.toml" {
		config, err = project.ReadProject(absolute)
		if err != nil {
			return loadError(filename, err)
		}
		options.Entry = !options.Tests && (!options.AnalyzeOnly || options.Entry)
	} else {
		config.Root, err = filepath.EvalSymlinks(config.Root)
		if err != nil {
			return loadError(filename, err)
		}
	}
	if options.Module != "" {
		config.Entry = options.Module
	}
	// Editors may address the same file through a symlinked workspace directory.
	// Reads and graph identity use canonical filenames, so overlays must too.
	if options.Overlay != nil {
		normalized := make(map[string]string, len(options.Overlay))
		for overlayFile, source := range options.Overlay {
			canonical, err := project.SourcePath(config.Root, overlayFile, options.Overlay)
			if err != nil {
				// Open documents outside this project do not enter its module graph.
				continue
			}
			if previous, ok := normalized[canonical]; ok && previous != source {
				return loadError(config.Entry, fmt.Errorf("conflicting editor overlays for %s", canonical))
			}
			normalized[canonical] = source
		}
		options.Overlay = normalized
	}
	var parseIssues []syntax.Diagnostic
	var modules []*syntax.Module
	imports := map[*syntax.Import]string{}
	active := map[string]bool{}
	loaded := map[string]*syntax.Module{}
	var visit func(string) (string, error)
	// Entry and imports cross the resolver once; the graph uses canonical keys.
	visit = func(canonical string) (string, error) {
		logical, _ := filepath.Rel(config.Root, canonical)
		logical = filepath.ToSlash(logical)
		if active[canonical] {
			return "", fmt.Errorf("cyclic module dependency at %s", logical)
		}
		if loaded[canonical] != nil {
			return logical, nil
		}
		active[canonical] = true
		defer delete(active, canonical)
		var source []byte
		var err error
		if text, ok := options.Overlay[canonical]; ok {
			source = []byte(text)
		} else {
			source, err = os.ReadFile(canonical)
		}
		if err != nil {
			return "", err
		}
		var module *syntax.Module
		if options.Recover && options.AnalyzeOnly {
			var issues []syntax.Diagnostic
			module, issues = parser.ParsePartial(logical, string(source))
			parseIssues = append(parseIssues, issues...)
		} else {
			module, err = parser.Parse(logical, string(source))
			if err != nil {
				return "", err
			}
		}
		loaded[canonical] = module
		for _, item := range module.Imports {
			if strings.HasPrefix(item.Path, "@std/") {
				continue
			}
			target, err := project.ResolveImport(config, canonical, item.Path, options.Overlay)
			var key string
			if err != nil {
				err = syntax.Diagnostic{Position: item.Pos, Phase: "resolution", Message: err.Error()}
			} else {
				key, err = visit(target)
			}
			if err != nil {
				if options.Recover && options.AnalyzeOnly {
					parseIssues = append(parseIssues, syntax.Diagnostic{Position: item.Pos, Phase: "resolution", Message: err.Error()})
					continue
				}
				return "", err
			}
			imports[item] = key
		}
		modules = append(modules, module)
		return logical, nil
	}
	entry, err := project.SourcePath(config.Root, config.Entry, options.Overlay)
	if err == nil {
		entry, err = visit(entry)
	}
	if err != nil {
		result := loadError(filename, err)
		result.SourceRoot = config.Root
		return result
	}
	result := compileModules(modules, imports, entry, options)
	result.SourceRoot = config.Root
	result.Diagnostics = append(parseIssues, result.Diagnostics...)
	if filepath.Base(absolute) == "ms.toml" {
		result.ProjectRoot = config.Root
		result.Configuration = config.Configuration
	}
	return result
}
func loadError(file string, err error) Result {
	if d, ok := err.(syntax.Diagnostic); ok {
		return Result{Diagnostics: []syntax.Diagnostic{d}}
	}
	return Result{Diagnostics: []syntax.Diagnostic{{Position: syntax.Position{File: file, Line: 1, Column: 1}, Phase: "resolution", Message: err.Error()}}}
}
