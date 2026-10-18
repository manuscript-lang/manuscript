package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// lintResultMatches reports a match whose only arms are ok and error. A
// compatible `try`, `if let` with `else`, or a Result method says the same
// thing directly.
func lintResultMatches(program *checker.Program) []LintFinding {
	var findings []LintFinding
	for e, info := range program.Expressions() {
		if e.Kind != syntax.KindMatch || len(e.Arms) != 2 || e.Left == nil {
			continue
		}
		scrutinee := program.Info(e.Left)
		if scrutinee == nil || scrutinee.Type == nil || scrutinee.Type.ID != "@std/Result" || info == nil {
			continue
		}
		ok, failed := false, false
		for _, arm := range e.Arms {
			switch arm.Path.Text {
			case "ok":
				ok = true
			case "error":
				failed = true
			}
		}
		if ok && failed {
			findings = append(findings, LintFinding{
				Code:     "MSL109",
				Message:  "Matching a Result with only ok and error; use 'try', 'if let value = ...:' with 'else:', or a Result method such as get(default), is_error, or err",
				Position: e.Pos,
			})
		}
	}
	return findings
}
