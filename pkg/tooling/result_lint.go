package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func lintDiscardedResults(program *checker.Program) []LintFinding {
	var findings []LintFinding
	visitor := syntax.Visitor{Statement: func(statement *syntax.Statement) {
		// KindCall represents expression statements, including standalone match.
		// Inspect only the discarded outer value: arguments and match arm values
		// may be consumed, and standalone try has already unwrapped to Unit.
		if statement.Kind != syntax.KindCall {
			return
		}
		info := program.Expressions[statement.Value]
		if info != nil && info.Type != nil && info.Type.ID == "@std/Result" {
			findings = append(findings, LintFinding{
				Code:     "MSL104",
				Message:  "Result is discarded; handle it with match or try, return it, or bind it to _ignored to discard intentionally",
				Position: statement.Pos,
			})
		}
	}}
	for _, module := range program.Modules {
		for _, declaration := range module.Declarations {
			visitor.Walk(declaration)
		}
	}
	return findings
}
