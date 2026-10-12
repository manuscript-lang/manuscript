// Package compiler exposes the parse, check, and Go generation pipeline.
package compiler

import (
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/syntax"
)

type Options struct {
	Recover bool
	// AnalyzeOnly omits native lowering; Module selects a project module for editor queries.
	AnalyzeOnly         bool
	Module, ScopeMarker string
	// Overlay contains absolute filenames with unsaved editor content.
	Overlay                        map[string]string
	CPUProfile, HeapProfile, Trace string
	Tests                          bool
	Entry                          bool
}
type Result struct {
	SourceRoot                 string
	Program                    *checker.Program
	Source                     string
	Diagnostics                []syntax.Diagnostic
	ProjectRoot, Configuration string
}

func (r Result) Success() bool { return len(r.Diagnostics) == 0 }
func CompileSource(filename, source string, options Options) Result {
	if options.Recover && options.AnalyzeOnly {
		module, issues := parser.ParsePartial(filename, source)
		result := compileModules([]*syntax.Module{module}, nil, module.File, options)
		result.Diagnostics = append(issues, result.Diagnostics...)
		return result
	}
	module, err := parser.Parse(filename, source)
	if err != nil {
		if d, ok := err.(syntax.Diagnostic); ok {
			return Result{Diagnostics: []syntax.Diagnostic{d}}
		}
		return Result{Diagnostics: []syntax.Diagnostic{{Position: syntax.Position{File: filename, Line: 1, Column: 1}, Phase: "parse", Message: err.Error()}}}
	}
	for _, i := range module.Imports {
		if len(i.Path) < 5 || i.Path[:5] != "@std/" {
			return Result{Diagnostics: []syntax.Diagnostic{{Position: i.Pos, Phase: "resolution", Message: "local imports require CompileFile"}}}
		}
	}
	return compileModules([]*syntax.Module{module}, nil, module.File, options)
}
func compileModules(modules []*syntax.Module, imports map[*syntax.Import]string, entry string, options Options) Result {
	checked := checker.CheckWithOptions(modules, imports, checker.CheckOptions{ScopeMarker: options.ScopeMarker})
	result := Result{Program: checked, Diagnostics: checked.Diagnostics}
	if !result.Success() || options.AnalyzeOnly {
		return result
	}
	if options.Entry {
		main := checked.Symbols[entry]["main"]
		if main == nil || !main.Export || main.Kind != "fn" || len(main.Variables) != 0 || len(main.Type.Params) != 0 || main.Type.Result.ID != "Int" {
			result.Diagnostics = append(result.Diagnostics, syntax.Diagnostic{Position: syntax.Position{File: entry, Line: 1, Column: 1}, Phase: "type", Message: "entry must export fn main() -> Int"})
			return result
		}
	}
	source, err := generate(checked, entry, options)
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, syntax.Diagnostic{Position: syntax.Position{File: entry, Line: 1, Column: 1}, Phase: "lowering", Message: err.Error()})
	} else {
		result.Source = source
	}
	return result
}
