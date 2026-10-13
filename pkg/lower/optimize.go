package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// optimizedProgram is a lowering view of checked source. Optimization facts
// live beside the AST so tooling keeps every source node, identity, and effect.
type optimizedProgram struct {
	program  *checker.Program
	booleans map[*syntax.Expression]bool
}

type booleanFolder struct {
	optimizedProgram
	visited map[*syntax.Expression]bool
}

// optimize folds boolean constants without evaluating calls or changing
// numeric fault behavior. Native optimization remains the Go compiler's job.
func optimize(program *checker.Program) optimizedProgram {
	optimized := optimizedProgram{program: program, booleans: map[*syntax.Expression]bool{}}
	folder := booleanFolder{optimizedProgram: optimized, visited: map[*syntax.Expression]bool{}}
	// Checking has already visited defaults, closures, and interpolation. Use
	// that expression inventory rather than introducing another AST traversal.
	for expression := range program.Expressions {
		folder.boolean(expression)
	}
	return optimized
}

func (p booleanFolder) boolean(e *syntax.Expression) (bool, bool) {
	if p.visited[e] {
		value, known := p.booleans[e]
		return value, known
	}
	p.visited[e] = true
	info := p.program.Expressions[e]
	if info == nil || info.Type.ID != "Bool" {
		return false, false
	}
	var value bool
	switch e.Kind {
	case syntax.KindBool:
		value = e.Text == "true"
	case syntax.KindUnary:
		if e.Text != "not" {
			return false, false
		}
		right, ok := p.boolean(e.Right)
		if !ok {
			return false, false
		}
		value = !right
	case syntax.KindBinary:
		if e.Text != "and" && e.Text != "or" {
			return false, false
		}
		left, ok := p.boolean(e.Left)
		if !ok {
			return false, false
		}
		// Only a constant left operand may eliminate the right operand. In
		// particular, effectful() and false must still evaluate effectful().
		if e.Text == "and" && !left || e.Text == "or" && left {
			value = left
		} else {
			right, ok := p.boolean(e.Right)
			if !ok {
				return false, false
			}
			value = right
		}
	default:
		return false, false
	}
	p.booleans[e] = value
	return value, true
}
