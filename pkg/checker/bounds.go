package checker

import (
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A bounds fact is a flow-sensitive proof about local bindings, used to narrow
// list[index] from Optional[T] to T. Facts concern only local List and Int
// bindings, are established by call-free guards, and die at an assignment to
// either binding or at anything that may mutate a list. Lowering keeps a
// checked read, so a lookup that a concurrent task invalidated faults like
// Optional.get() instead of reading out of range.
type boundFact struct {
	kind        byte // 'n': index >= 0; 'u': index < list.length(); 'l': list.length() >= min
	list, index *Binding
	min         int
	dead        bool
}

const (
	factNonNegative = 'n'
	factUpper       = 'u'
	factLength      = 'l'
)

func (c *checker) liveFact(kind byte, list, index *Binding, min int) bool {
	for _, f := range c.facts {
		if !f.dead && f.kind == kind && f.list == list && f.index == index && f.min >= min {
			return true
		}
	}
	return false
}

func (c *checker) nonNegative(b *Binding) bool {
	return b.nonNegative || c.liveFact(factNonNegative, nil, b, 0)
}

// killAssigned drops every fact that mentions a reassigned binding.
func (c *checker) killAssigned(b *Binding) {
	for _, f := range c.facts {
		if f.list == b || f.index == b {
			f.dead = true
		}
	}
}

// killMutations drops facts about list lengths; Int facts survive because a
// callee cannot reassign a caller's local.
func (c *checker) killMutations() {
	for _, f := range c.facts {
		if f.kind != factNonNegative {
			f.dead = true
		}
	}
}

func (c *checker) pushFacts(facts []*boundFact) { c.facts = append(c.facts, facts...) }

func (c *checker) localOf(e *syntax.Expression) *Binding {
	if e == nil || e.Kind != syntax.KindName {
		return nil
	}
	return c.scope.binding(e.Text)
}

func (c *checker) localList(e *syntax.Expression) *Binding {
	if b := c.localOf(e); b != nil && std(b.Type, "List") && len(b.Type.Args) == 1 {
		return b
	}
	return nil
}

func (c *checker) localInt(e *syntax.Expression) *Binding {
	if b := c.localOf(e); b != nil && b.Type.ID == "Int" {
		return b
	}
	return nil
}

// listLength recognizes `name.length()` on a local List.
func (c *checker) listLength(e *syntax.Expression) *Binding {
	if e == nil || e.Kind != syntax.KindCall || len(e.Args) != 0 || e.Left == nil || e.Left.Kind != syntax.KindMember || e.Left.Text != "length" {
		return nil
	}
	return c.localList(e.Left.Left)
}

// intConstant reads a written integer, including a leading minus.
func intConstant(e *syntax.Expression) (int, bool) {
	if e == nil {
		return 0, false
	}
	if e.Kind == syntax.KindUnary && e.Text == "-" {
		n, ok := intConstant(e.Right)
		return -n, ok && n > 0
	}
	if e.Kind != syntax.KindNumber {
		return 0, false
	}
	n, err := strconv.ParseInt(strings.ReplaceAll(e.Text, "_", ""), 0, 32)
	return int(n), err == nil
}

// pureCall reports a call that cannot mutate any list: length() on a local
// collection or String.
func (c *checker) pureCall(e *syntax.Expression) bool {
	if e.Kind != syntax.KindCall || len(e.Args) != 0 || e.Left == nil || e.Left.Kind != syntax.KindMember || e.Left.Text != "length" {
		return false
	}
	b := c.localOf(e.Left.Left)
	return b != nil && (b.Type.ID == "String" || std(b.Type, "List") || std(b.Type, "Map") || std(b.Type, "Set"))
}

// effects counts the expressions in e that may run arbitrary code. Each call
// or closure counts once; paths records, for every index expression, how many
// of them enclose it.
func (c *checker) effects(e *syntax.Expression, enclosing int, paths map[*syntax.Expression]int) int {
	if e == nil {
		return 0
	}
	own := 0
	switch e.Kind {
	case syntax.KindCall:
		if !c.pureCall(e) {
			own = 1
		}
	case syntax.KindLambda, syntax.KindMatch:
		own = 1
	case syntax.KindIndex:
		paths[e] = enclosing
	case syntax.KindApply:
		// A bracket with a plain name parses as a type application until checked.
		if e.Right != nil {
			paths[e] = enclosing
		}
	}
	total := own
	total += c.effects(e.Left, enclosing+own, paths)
	total += c.effects(e.Right, enclosing+own, paths)
	for _, a := range e.Args {
		total += c.effects(a.Value, enclosing+own, paths)
	}
	for _, v := range e.Elements {
		total += c.effects(v, enclosing+own, paths)
	}
	for _, p := range e.Parts {
		total += c.effects(p.Value, enclosing+own, paths)
	}
	return total
}

func (c *checker) callFree(e *syntax.Expression) bool {
	return c.effects(e, 0, map[*syntax.Expression]int{}) == 0
}

// analyzeStatement allows a bounds proof on the lookups of a statement's own
// expressions whose evaluation no other call can interleave with, and reports
// whether the statement may mutate lists.
func (c *checker) analyzeStatement(s *syntax.Statement) (allowed map[*syntax.Expression]bool, mutates bool) {
	paths := map[*syntax.Expression]int{}
	total := c.effects(s.Target, 0, paths) + c.effects(s.Value, 0, paths)
	allowed = map[*syntax.Expression]bool{}
	for e, enclosing := range paths {
		allowed[e] = enclosing == total
	}
	return allowed, total > 0
}

// comparison normalizes a < b, a <= b, a > b, and a >= b to lo < hi or lo <= hi.
func comparison(e *syntax.Expression, positive bool) (lo, hi *syntax.Expression, strict, ok bool) {
	if e.Kind != syntax.KindBinary {
		return
	}
	switch e.Text {
	case "<":
		lo, hi, strict = e.Left, e.Right, true
	case "<=":
		lo, hi, strict = e.Left, e.Right, false
	case ">":
		lo, hi, strict = e.Right, e.Left, true
	case ">=":
		lo, hi, strict = e.Right, e.Left, false
	default:
		return
	}
	if !positive {
		// not (lo < hi) is hi <= lo; not (lo <= hi) is hi < lo.
		lo, hi, strict = hi, lo, !strict
	}
	return lo, hi, strict, true
}

// guardFacts derives what holds when cond is true (positive) or false. A
// condition containing calls establishes nothing.
func (c *checker) guardFacts(cond *syntax.Expression, positive bool) []*boundFact {
	if cond == nil || !c.callFree(cond) {
		return nil
	}
	return c.facts_of(cond, positive)
}

func (c *checker) facts_of(e *syntax.Expression, positive bool) []*boundFact {
	switch {
	case e.Kind == syntax.KindUnary && e.Text == "not":
		return c.facts_of(e.Right, !positive)
	case e.Kind == syntax.KindBinary && (e.Text == "and") == positive && (e.Text == "and" || e.Text == "or"):
		return append(c.facts_of(e.Left, positive), c.facts_of(e.Right, positive)...)
	}
	lo, hi, strict, ok := comparison(e, positive)
	if !ok {
		return nil
	}
	var facts []*boundFact
	if n, isConstant := intConstant(lo); isConstant {
		if index := c.localInt(hi); index != nil && ((strict && n >= -1) || n >= 0) {
			facts = append(facts, &boundFact{kind: factNonNegative, index: index})
		}
		if list := c.listLength(hi); list != nil {
			min := n
			if strict {
				min++
			}
			if min > 0 {
				facts = append(facts, &boundFact{kind: factLength, list: list, min: min})
			}
		}
	}
	if index, list := c.localInt(lo), c.listLength(hi); index != nil && list != nil && strict {
		facts = append(facts, &boundFact{kind: factUpper, list: list, index: index})
	}
	return facts
}

// proven reports that e, a lookup on a local List, is in range here.
func (c *checker) proven(e *syntax.Expression) bool {
	if !c.allowedLookups[e] {
		return false
	}
	list := c.localList(e.Left)
	if list == nil {
		return false
	}
	if n, ok := intConstant(e.Right); ok {
		return n >= 0 && c.liveFact(factLength, list, nil, n+1)
	}
	index := c.localInt(e.Right)
	return index != nil && c.nonNegative(index) && c.liveFact(factUpper, list, index, 0)
}

// safeIncrement reports an assignment that keeps a nonnegative Int nonnegative.
func safeIncrement(name string, value *syntax.Expression) bool {
	if n, ok := intConstant(value); ok {
		return n >= 0
	}
	if value.Kind == syntax.KindBinary && value.Text == "+" && value.Left.Kind == syntax.KindName && value.Left.Text == name {
		n, ok := intConstant(value.Right)
		return ok && n >= 0
	}
	return false
}

// enterLoop invalidates facts the body can break before they are reached
// again through the back edge. Names are matched without scope resolution, so
// a shadowing assignment can only invalidate more.
func (c *checker) enterLoop(body []*syntax.Statement) {
	mutates := false
	syntax.Visitor{
		Statement: func(s *syntax.Statement) {
			if s.Kind != syntax.KindAssign || s.Target != nil {
				return
			}
			b := c.scope.binding(s.Name)
			if b == nil {
				return
			}
			if b.nonNegative && !safeIncrement(s.Name, s.Value) {
				b.nonNegative = false
			}
			c.killAssigned(b)
		},
		Expression: func(e *syntax.Expression) {
			if e.Kind == syntax.KindCall || e.Kind == syntax.KindLambda {
				mutates = true
			}
		},
	}.Callable(nil, body)
	if mutates {
		c.killMutations()
	}
}
