// Package frontend parses Manuscript source and loads dependency-ordered ASTs.
// It does not check types, lower code, or depend on the native toolchain.
package frontend

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Options selects editor recovery and source snapshots for graph loading.
type Options struct {
	// Tests adds the project's test.ms and *_test.ms files to the module graph.
	Tests bool
	// ProjectSources adds all source modules and project tests, including unimported files.
	ProjectSources bool
	Recover        bool
	// Module selects an editor module within a project's root.
	Module string
	// Overlay maps absolute filenames to unsaved source.
	Overlay map[string]string
}

// Graph retains original syntax and the canonical identity of each import.
// Modules are in dependency order. Diagnostics may accompany recovered ASTs;
// callers must retain them when checking and must never lower invalid source.
type Graph struct {
	Modules                    []*syntax.Module
	Imports                    map[*syntax.Import]string
	Entry                      string
	SourceRoot                 string
	ProjectRoot, Configuration string
	Diagnostics                []syntax.Diagnostic
}

// Parse is the shared parsing stage for compilation and syntax-only tools.
// Recovery retains independent declarations and their original positions.
func Parse(filename, source string, recover bool) (*syntax.Module, []syntax.Diagnostic) {
	if recover {
		return parser.ParsePartial(filename, source)
	}
	module, err := parser.Parse(filename, source)
	if err != nil {
		return nil, []syntax.Diagnostic{diagnostic(filename, "parse", err)}
	}
	return module, nil
}

// LoadSource parses in-memory source without filesystem resolution.
func LoadSource(filename, source string, options Options) Graph {
	module, issues := Parse(filename, source, options.Recover)
	graph := Graph{Entry: filename, Diagnostics: issues}
	if module == nil {
		return graph
	}
	for _, item := range module.Imports {
		if !strings.HasPrefix(item.Path, "@std/") {
			graph.Diagnostics = append(graph.Diagnostics, syntax.Diagnostic{Position: item.Pos, Phase: "resolution", Message: "local imports require CompileFile"})
			if !options.Recover {
				return graph
			}
		}
	}
	graph.Modules = []*syntax.Module{module}
	return graph
}

func diagnostic(filename, phase string, err error) syntax.Diagnostic {
	if issue, ok := err.(syntax.Diagnostic); ok {
		return issue
	}
	return syntax.Diagnostic{Position: syntax.Position{File: filename, Line: 1, Column: 1}, Phase: phase, Message: explainPathError(err, "")}
}

// explainPathError turns raw filesystem failures into a cause and a fix.
// importPath is the import string when the failure came from an import.
func explainPathError(err error, importPath string) string {
	var pathError *fs.PathError
	if !errors.As(err, &pathError) {
		return err.Error()
	}
	name := pathError.Path
	if relative, relErr := filepath.Rel(mustGetwd(), name); relErr == nil && !strings.HasPrefix(relative, "..") {
		name = relative
	}
	switch {
	case errors.Is(err, fs.ErrNotExist) && importPath != "":
		return "cannot find module " + importPath + " (looked for " + name + "); check the spelling, make sure the file exists, and that the path is relative to the importing file"
	case errors.Is(err, fs.ErrNotExist):
		return "file not found: " + name + "; check the path, pass a .ms file or a project ms.toml, and run from the directory that contains it"
	case errors.Is(err, fs.ErrPermission):
		return "permission denied reading " + name + "; make the file readable"
	}
	return err.Error()
}

func mustGetwd() string {
	wd, err := os.Getwd()
	if err != nil {
		return ""
	}
	return wd
}
