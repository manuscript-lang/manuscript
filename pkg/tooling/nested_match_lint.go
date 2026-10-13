package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func lintNestedMatches(program *checker.Program) []LintFinding {
	var findings []LintFinding
	for _, module := range program.Modules {
		for _, match := range syntax.NestedMatches(module) {
			findings = append(findings, LintFinding{
				Code:     "MSL107",
				Message:  "Nested match obscures control flow; bind the outer payload with an early exit, use compatible try, or call a small helper",
				Position: match.Pos,
			})
		}
	}
	return findings
}
