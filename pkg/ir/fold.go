package ir

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Elaborator turns checked expressions into IR nodes. It also decides which
// Bool expressions are compile-time constants, folding without evaluating
// calls or changing numeric fault behavior; native optimization stays the Go
// compiler's job.
type Elaborator struct {
	program *checker.Program
	known   map[*syntax.Expression]fold
}

type fold struct{ value, constant bool }

// NewElaborator returns an Elaborator for program.
func NewElaborator(program *checker.Program) *Elaborator {
	return &Elaborator{program: program, known: map[*syntax.Expression]fold{}}
}

// Bool reports the constant value of e and whether e is a constant.
func (f *Elaborator) Bool(e *syntax.Expression) (value, constant bool) {
	if known, ok := f.known[e]; ok {
		return known.value, known.constant
	}
	value, constant = f.fold(e)
	f.known[e] = fold{value, constant}
	return value, constant
}

func (f *Elaborator) fold(e *syntax.Expression) (bool, bool) {
	info := f.program.Info(e)
	if info == nil || info.Type.ID != "Bool" {
		return false, false
	}
	switch e.Kind {
	case syntax.KindBool:
		return e.Text == "true", true
	case syntax.KindUnary:
		if e.Text != "not" {
			return false, false
		}
		right, ok := f.Bool(e.Right)
		return !right, ok
	case syntax.KindBinary:
		if e.Text != "and" && e.Text != "or" {
			return false, false
		}
		left, ok := f.Bool(e.Left)
		if !ok {
			return false, false
		}
		// Only a constant left operand may eliminate the right operand. In
		// particular, effectful() and false must still evaluate effectful().
		if e.Text == "and" && !left || e.Text == "or" && left {
			return left, true
		}
		return f.Bool(e.Right)
	}
	return false, false
}
