package cli

import (
	"path/filepath"
	"sort"

	"github.com/manuscript-lang/manuscript/internal/debugger"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/lower"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

// debugNames maps the generated Go names in a Debug build back to Manuscript
// source using the same inspection that ms inspect reports.
func debugNames(result compiler.Result) debugger.Names {
	root, _ := filepath.Abs(result.SourceRoot)
	names := namesFromInspection(root, tooling.Inspect(result.Program))
	// Lowering again names the Go local of every binding; the Go it produces
	// is the same as the Debug build's for every function both reach.
	_, _ = lower.Go(result.Program, "", lower.Options{Tests: true, Locals: func(function, goName string, b *checker.Binding) {
		if names.Locals[function] == nil {
			names.Locals[function] = map[string]debugger.Local{}
		}
		names.Locals[function][goName] = debugger.Local{Name: b.Name, Type: b.Type.String()}
	}})
	return names
}

func namesFromInspection(root string, inspection tooling.Inspection) debugger.Names {
	names := debugger.Names{Root: root, Locals: map[string]map[string]debugger.Local{}, Sources: map[string]bool{}, Lines: map[string]map[int]bool{}}
	for _, source := range inspection.Sources {
		names.Sources[filepath.ToSlash(source.File)] = true
	}
	for _, entity := range inspection.Entities {
		file := filepath.ToSlash(entity.Span.File)
		function := entity.Kind == syntax.KindFn || entity.Kind == syntax.KindTest || entity.Kind == "method" || entity.Kind == "accessor" && entity.GoID != ""
		names.Entities = append(names.Entities, debugger.Entity{
			Name: entity.Name, File: file, Line: entity.Span.Line, Function: function,
			Body: firstStatementAfter(inspection.Statements, entity.Span),
		})
	}
	for _, statement := range inspection.Statements {
		markLine(&names, statement)
	}
	for _, entity := range inspection.Entities {
		markLine(&names, entity.Span)
	}
	sort.SliceStable(names.Entities, func(i, j int) bool {
		a, b := names.Entities[i], names.Entities[j]
		return a.File < b.File || a.File == b.File && a.Line < b.Line
	})
	return names
}

// firstStatementAfter is the line of the first executable statement after a
// declaration header, so a function breakpoint stops before its body runs.
func firstStatementAfter(statements []tooling.Span, header tooling.Span) int {
	best := 0
	for _, statement := range statements {
		if statement.File == header.File && statement.Start > header.Start && (best == 0 || statement.Start < best) {
			best = statement.Start
		}
	}
	if best == 0 {
		return header.Line + 1
	}
	for _, statement := range statements {
		if statement.File == header.File && statement.Start == best {
			return statement.Line
		}
	}
	return header.Line + 1
}

func markLine(names *debugger.Names, span tooling.Span) {
	file := filepath.ToSlash(span.File)
	if names.Lines[file] == nil {
		names.Lines[file] = map[int]bool{}
	}
	names.Lines[file][span.Line] = true
}
