package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Pass: constant folding. After checking, every Bool expression that is a
// compile-time constant is annotated with its value (Info.Folded and
// Info.Constant). Folding never evaluates calls or changes numeric fault
// behavior: only a constant left operand may drop the right operand, so
// `effectful() and false` still runs effectful(). Native optimization stays
// the Go compiler's job.
func foldConstants(modules []*syntax.Module) {
	for _, module := range modules {
		syntax.Nodes{Expression: func(e *syntax.Expression) { foldBool(e) }}.Module(module)
	}
}

// foldBool reports the constant value of e and whether e is a constant,
// recording it on e's facts.
func foldBool(e *syntax.Expression) (value, constant bool) {
	info := infoOf(e)
	if info == nil || info.Type == nil || info.Type.ID != "Bool" {
		return false, false
	}
	if info.foldDone {
		return info.Constant, info.Folded
	}
	value, constant = fold(e)
	info.Constant, info.Folded, info.foldDone = value, constant, true
	return value, constant
}

func fold(e *syntax.Expression) (bool, bool) {
	switch e.Kind {
	case syntax.KindBool:
		return e.Text == "true", true
	case syntax.KindUnary:
		if e.Text != "not" {
			return false, false
		}
		right, ok := foldBool(e.Right)
		return !right, ok
	case syntax.KindBinary:
		if e.Text != "and" && e.Text != "or" {
			return false, false
		}
		left, ok := foldBool(e.Left)
		if !ok {
			return false, false
		}
		// Only a constant left operand may eliminate the right operand.
		if e.Text == "and" && !left || e.Text == "or" && left {
			return left, true
		}
		return foldBool(e.Right)
	}
	return false, false
}
