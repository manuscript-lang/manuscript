// Package compiler runs Manuscript's shared source-to-Go pipeline.
package compiler

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/project"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type Options struct {
	// Recover retains valid declarations in unfinished editor source. It is
	// honored only with AnalyzeOnly; executable compilation is always strict.
	Recover bool
	// AnalyzeOnly stops after type checking and optional entry validation.
	AnalyzeOnly bool
	// Module selects a project module; ScopeMarker captures its editor scope.
	Module, ScopeMarker string
	// Overlay contains absolute filenames with unsaved editor content.
	Overlay                        map[string]string
	CPUProfile, HeapProfile, Trace string
	Tests                          bool
	// Entry requires an exported, nongeneric, parameterless main returning Int.
	Entry bool
}
type Result struct {
	SourceRoot                 string
	Program                    *checker.Program
	Source                     string
	Diagnostics                []syntax.Diagnostic
	ProjectRoot, Configuration string
}

func (r Result) Success() bool { return len(r.Diagnostics) == 0 }

// Project and ReadProject retain the compiler API for manifest-only callers.
type Project = project.Project

func ReadProject(filename string) (Project, error) { return project.ReadProject(filename) }

// CompileSource parses in-memory source. Local imports require CompileFile.
func CompileSource(filename, source string, options Options) Result {
	graph := frontend.LoadSource(filename, source, options.sourceOptions())
	return compile(graph, options)
}

// CompileFile loads a module or project and checks its reachable import graph.
func CompileFile(filename string, options Options) Result {
	graph := frontend.LoadFile(filename, options.sourceOptions())
	if graph.ProjectRoot != "" {
		options.Entry = !options.Tests && (!options.AnalyzeOnly || options.Entry)
	}
	return compile(graph, options)
}

func (o Options) sourceOptions() frontend.Options {
	return frontend.Options{Recover: o.Recover && o.AnalyzeOnly, Module: o.Module, Overlay: o.Overlay, Tests: o.Tests}
}

// compile is the common path after parsing and import resolution. Each stage
// consumes the previous stage's result; tools stop at the checked source model.
func compile(graph frontend.Graph, options Options) Result {
	result := Result{
		SourceRoot: graph.SourceRoot, ProjectRoot: graph.ProjectRoot,
		Configuration: graph.Configuration, Diagnostics: graph.Diagnostics,
	}
	if len(graph.Modules) == 0 {
		return result
	}

	checked := checker.CheckWithOptions(graph.Modules, graph.Imports, checker.CheckOptions{ScopeMarker: options.ScopeMarker})
	result.Program = checked
	result.Diagnostics = append(result.Diagnostics, checked.Diagnostics...)
	if !result.Success() {
		return result
	}
	if options.Entry {
		if issue := checkEntry(checked, graph.Entry); issue != nil {
			result.Diagnostics = append(result.Diagnostics, *issue)
			return result
		}
	}
	if options.AnalyzeOnly {
		return result
	}

	optimized := optimize(checked)
	source, err := lowerGo(optimized, graph.Entry, options)
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, syntax.Diagnostic{Position: syntax.Position{File: graph.Entry, Line: 1, Column: 1}, Phase: "lowering", Message: err.Error()})
	} else {
		result.Source = source
	}
	return result
}

func checkEntry(program *checker.Program, entry string) *syntax.Diagnostic {
	main := program.Symbols[entry]["main"]
	if main != nil && main.Export && main.Kind == syntax.KindFn && len(main.Variables) == 0 && len(main.Type.Params) == 0 && main.Type.Result.ID == "Int" {
		return nil
	}
	position := syntax.Position{File: entry, Line: 1, Column: 1}
	detail := "no main function is declared, so add 'export fn main() -> Int:' with an indented 'return 0' body"
	if main != nil {
		if main.Decl != nil {
			position = main.Decl.Pos
		}
		switch {
		case main.Kind != syntax.KindFn:
			detail = "main is declared as a " + main.Kind + ", so rename it and declare 'export fn main() -> Int:'"
		case !main.Export:
			detail = "main is not exported, so write 'export fn main() -> Int:'"
		case len(main.Variables) > 0:
			detail = "main cannot be generic, so remove its type parameters"
		case len(main.Type.Params) > 0:
			detail = "main takes no parameters, so remove them (read program arguments through the standard cli module)"
		default:
			detail = "main returns " + main.Type.Result.String() + ", so declare it '-> Int' and return an exit status, e.g. 'return 0'"
		}
	}
	return &syntax.Diagnostic{Position: position, Phase: "type", Message: "entry must export fn main() -> Int; " + detail}
}
