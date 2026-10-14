package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// lintBareArguments reports a bare identifier whose matching-name shorthand
// selects a different parameter than the next positional slot would. Binding is
// unchanged; the advisory exposes the effective mapping at the call site.
func lintBareArguments(program *checker.Program) []LintFinding {
	var findings []LintFinding
	for call, info := range program.Expressions() {
		if call.Kind != syntax.KindCall || info == nil || len(info.Arguments) != len(call.Args) {
			continue
		}
		params := callParameters(program, call, info)
		if len(params) <= 1 {
			continue
		}
		seen := map[string]bool{}
		for at, arg := range call.Args {
			label := info.Arguments[at].Name
			if arg.Name == "" && label == arg.Value.Text && arg.Value.Kind == syntax.KindName && arg.Pos == arg.Value.Pos {
				slot := ""
				for _, name := range params {
					if !seen[name] {
						slot = name
						break
					}
				}
				if slot != "" && slot != label {
					findings = append(findings, LintFinding{
						Code: "MSL109",
						Message: "Bare identifier " + label + " selects parameter " + label + ", not the next positional parameter " + slot +
							"; write " + slot + ": " + label + " or (" + label + ") for positional intent, or " + label + ": " + label + " to keep this binding",
						Position: arg.Pos,
					})
				}
			}
			seen[label] = true
		}
	}
	return findings
}

// callParameters lists the parameter or field names a call fills, in slot order.
func callParameters(program *checker.Program, call *syntax.Expression, info *checker.Info) []string {
	var names []string
	add := func(params []checker.Param) {
		for _, param := range params {
			names = append(names, param.Name)
		}
	}
	if info.Constructor != nil {
		if info.Case == "" {
			add(checker.Fields(info.Constructor))
			return names
		}
		for _, cs := range checker.Cases(info.Constructor) {
			if cs.Name == info.Case {
				add(cs.Fields)
			}
		}
		return names
	}
	if called := program.Info(call.Left); called != nil && called.Type != nil {
		add(called.Type.Params)
	}
	return names
}
