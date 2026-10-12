// Package frontend parses Manuscript source and loads dependency-ordered ASTs.
// It does not check types, lower code, or depend on the native toolchain.
package frontend

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Options selects editor recovery and source snapshots for graph loading.
type Options struct {
	Recover bool
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
	return syntax.Diagnostic{Position: syntax.Position{File: filename, Line: 1, Column: 1}, Phase: phase, Message: err.Error()}
}
