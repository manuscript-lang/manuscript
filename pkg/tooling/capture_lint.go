package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// lintSharedCaptures recognizes direct writes in inline concurrent callbacks.
// It deliberately does not infer aliasing, helper effects, or lock ownership.
func lintSharedCaptures(program *checker.Program) []LintFinding {
	var findings []LintFinding
	for call, info := range program.Expressions {
		if call.Kind != syntax.KindCall || info == nil || info.Method == nil || info.Method.Receiver == nil || info.Method.Decl == nil {
			continue
		}
		argument := ""
		switch info.Method.Receiver.ID {
		case "@std/TaskGroup":
			if info.Method.Decl.Name == "start" {
				argument = "operation"
			}
		case "@std/Scheduler":
			switch info.Method.Decl.Name {
			case "start", "after", "every":
				argument = "operation"
			}
		case "@std/Network":
			switch info.Method.Decl.Name {
			case "serve", "serve_stream":
				argument = "handler"
			}
		}
		if argument == "" {
			continue
		}
		for _, arg := range info.Arguments {
			callback := arg.Value
			if arg.Name != argument || callback == nil || callback.Kind != syntax.KindLambda {
				continue
			}
			callbackInfo := program.Expressions[callback]
			if callbackInfo == nil {
				continue
			}
			captures := map[*checker.Binding]bool{}
			for _, binding := range callbackInfo.Captures {
				captures[binding] = true
			}

			// Shared traversal visits nested lambdas too. Exclude their bodies:
			// creating an unrelated function is not executing its mutations.
			nestedStatements := map[*syntax.Statement]bool{}
			nestedExpressions := map[*syntax.Expression]bool{}
			syntax.Visitor{Expression: func(e *syntax.Expression) {
				if e.Kind != syntax.KindLambda {
					return
				}
				syntax.Visitor{
					Statement:  func(s *syntax.Statement) { nestedStatements[s] = true },
					Expression: func(e *syntax.Expression) { nestedExpressions[e] = true },
				}.Callable(e.Params, e.Body)
			}}.Callable(callback.Params, callback.Body)
			report := func(receiver *syntax.Expression, pos syntax.Position) {
				if receiver == nil || receiver.Kind != syntax.KindName {
					return
				}
				receiverInfo := program.Expressions[receiver]
				if receiverInfo == nil || !captures[receiverInfo.Binding] {
					return
				}
				findings = append(findings, LintFinding{
					"MSL105",
					"Concurrent callback mutates captured value " + receiverInfo.Binding.Name + "; protect shared access with Synchronized and mutate the value through its guard",
					pos,
				})
			}
			syntax.Visitor{
				Statement: func(s *syntax.Statement) {
					if nestedStatements[s] || s.Kind != syntax.KindAssign || s.Target == nil || s.Target.Kind != syntax.KindMember {
						return
					}
					receiver := s.Target.Left
					if receiverInfo := program.Expressions[receiver]; receiverInfo != nil && receiverInfo.Type != nil && receiverInfo.Type.Kind == syntax.KindRecord {
						report(receiver, s.Target.Pos)
					}
				},
				Expression: func(e *syntax.Expression) {
					if nestedExpressions[e] || e.Kind != syntax.KindCall || e.Left == nil || e.Left.Kind != syntax.KindMember {
						return
					}
					info := program.Expressions[e]
					if info == nil || info.Method == nil || info.Method.Decl == nil {
						return
					}
					if checker.CollectionMutation(info.Method.Receiver, info.Method.Decl.Name) {
						report(e.Left.Left, e.Pos)
					}
				},
			}.Callable(callback.Params, callback.Body)
		}
	}
	return findings
}
