package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// lintOptionalMatches reports a match whose only arms are some and none; an
// `if let` with `else`, or an Optional method, says the same thing directly.
func lintOptionalMatches(program *checker.Program) []LintFinding {
	return lintTwoArmMatches(program, "@std/Optional", "some", "none", LintFinding{
		Code:    "MSL108",
		Message: "Matching an Optional with only some and none; use 'if let value = ...:' with 'else:', or an Optional method such as get(default) or map",
	})
}

// lintResultMatches reports a match whose only arms are ok and error. A
// compatible `try`, `if let` with `else`, or a Result method says the same
// thing directly.
func lintResultMatches(program *checker.Program) []LintFinding {
	return lintTwoArmMatches(program, "@std/Result", "ok", "error", LintFinding{
		Code:    "MSL109",
		Message: "Matching a Result with only ok and error; use 'try', 'if let value = ...:' with 'else:', or a Result method such as get(default), is_error, or err",
	})
}

// lintTwoArmMatches reports each match on a value of type id that has exactly
// the arms first and second, one finding per match built from template.
func lintTwoArmMatches(program *checker.Program, id, first, second string, template LintFinding) []LintFinding {
	var findings []LintFinding
	for e, info := range program.Expressions() {
		if e.Kind != syntax.KindMatch || len(e.Arms) != 2 || e.Left == nil || info == nil {
			continue
		}
		scrutinee := program.Info(e.Left)
		if scrutinee == nil || scrutinee.Type == nil || scrutinee.Type.ID != id {
			continue
		}
		hasFirst, hasSecond := false, false
		for _, arm := range e.Arms {
			switch arm.Path.Text {
			case first:
				hasFirst = true
			case second:
				hasSecond = true
			}
		}
		if hasFirst && hasSecond {
			finding := template
			finding.Position = e.Pos
			findings = append(findings, finding)
		}
	}
	return findings
}
