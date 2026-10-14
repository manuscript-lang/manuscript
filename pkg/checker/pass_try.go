package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Pass: try shape. A statement that binds, assigns, returns, or evaluates a
// whole `try expr` (not an Error-boundary conversion) is marked, so lowering
// emits an early return for it instead of unwinding through deferred handlers.
func markPlainTry(modules []*syntax.Module) {
	for _, module := range modules {
		syntax.Nodes{Statement: func(s *syntax.Statement) {
			if s.Value == nil || s.Target != nil {
				return
			}
			switch s.Kind {
			case syntax.KindBind, syntax.KindAssign, syntax.KindReturn, syntax.KindCall:
			default:
				return
			}
			e := s.Value
			if info := infoOf(e); e.Kind == syntax.KindUnary && e.Text == "try" && info != nil && info.ErrorSource == nil {
				writableStatementFacts(s).plainTry = true
			}
		}}.Module(module)
	}
}
