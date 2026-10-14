package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// analyzed is a checked in-memory module. Lowering tests start from checked
// programs without importing the compiler pipeline that depends on this package.
type analyzed struct {
	Program     *checker.Program
	Diagnostics []syntax.Diagnostic
}

func (a analyzed) Success() bool { return len(a.Diagnostics) == 0 }

func analyzeSource(filename, source string) analyzed {
	graph := frontend.LoadSource(filename, source, frontend.Options{})
	result := analyzed{Diagnostics: graph.Diagnostics}
	if len(graph.Modules) == 0 {
		return result
	}
	result.Program = checker.CheckWithOptions(graph.Modules, graph.Imports, checker.CheckOptions{})
	result.Diagnostics = append(result.Diagnostics, result.Program.Diagnostics...)
	return result
}

type compiled struct {
	analyzed
	Source string
}

// compileSource checks and lowers one module, as the compiler pipeline does.
func compileSource(filename, source string) compiled {
	result := compiled{analyzed: analyzeSource(filename, source)}
	if !result.Success() {
		return result
	}
	generated, err := Go(result.Program, filename, Options{})
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, syntax.Diagnostic{Position: syntax.Position{File: filename, Line: 1, Column: 1}, Phase: "lowering", Message: err.Error()})
		return result
	}
	result.Source = generated
	return result
}
