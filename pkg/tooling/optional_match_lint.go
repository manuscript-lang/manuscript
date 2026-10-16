package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// lintOptionalMatches reports a match whose only arms are some and none; an
// `if let` with `else`, or an Optional method, says the same thing directly.
func lintOptionalMatches(program *checker.Program) []LintFinding {
	var findings []LintFinding
	for e, info := range program.Expressions() {
		if e.Kind != syntax.KindMatch || len(e.Arms) != 2 || e.Left == nil {
			continue
		}
		scrutinee := program.Info(e.Left)
		if scrutinee == nil || scrutinee.Type == nil || scrutinee.Type.ID != "@std/Optional" || info == nil {
			continue
		}
		some, none := false, false
		for _, arm := range e.Arms {
			switch arm.Path.Text {
			case "some":
				some = true
			case "none":
				none = true
			}
		}
		if some && none {
			findings = append(findings, LintFinding{
				Code:     "MSL108",
				Message:  "Matching an Optional with only some and none; use 'if let value = ...:' with 'else:', or an Optional method such as unwrap_or or map",
				Position: e.Pos,
			})
		}
	}
	return findings
}
