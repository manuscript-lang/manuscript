package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Pass: argument order. After checking, every call carries its arguments in
// written order with omitted function labels resolved (Info.Arguments). Calls
// the checker did not relabel keep their written arguments, so lowering reads
// one list and never asks whether labels were resolved.
func orderArguments(modules []*syntax.Module) {
	for _, module := range modules {
		syntax.Nodes{Expression: func(e *syntax.Expression) {
			if info := infoOf(e); info != nil && info.Arguments == nil {
				info.Arguments = e.Args
			}
		}}.Module(module)
	}
}

// finishModules runs the passes that make checked trees ready for lowering.
func finishModules(modules []*syntax.Module) {
	foldConstants(modules)
	orderArguments(modules)
}
