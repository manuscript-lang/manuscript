package lower

import (
	"math/big"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Empty elements are bottom, not unknown. Immutable summaries let journal
// rollback share them without changing an earlier fact.
type listBounds struct {
	length      intBounds
	elements    intBounds
	hasElements bool
}

func (b listBounds) including(value intBounds) listBounds {
	if !b.hasElements {
		b.elements = value
		b.hasElements = true
	} else {
		b.elements = intBounds{min(b.elements.lo, value.lo), max(b.elements.hi, value.hi)}
	}
	return b
}
func (p *intProof) listCall(e *syntax.Expression) localListCall {
	if p.g.fn.localCollections != nil {
		return p.g.fn.localCollections.listCalls[e]
	}
	return localListCall{}
}
func (p *intProof) closedList(b *checker.Binding) bool {
	return p.g.fn.localCollections != nil && p.g.fn.localCollections.lists[b]
}
func (p *intProof) getList(b *checker.Binding) *listBounds {
	if f, ok := p.facts[b]; ok && f.epoch == p.epoch {
		return f.list
	}
	return nil
}
func (p *intProof) setList(b *checker.Binding, bounds *listBounds) {
	old, had := p.facts[b]
	p.journal = append(p.journal, intUndo{b, old, had})
	p.facts[b] = intFact{epoch: p.epoch, list: bounds}
}
func (p *intProof) literalList(e *syntax.Expression) *listBounds {
	if e == nil || e.Kind != syntax.KindList || p.hazardous(e) {
		return nil
	}
	n := int64(len(e.Elements))
	bounds := listBounds{length: intBounds{n, n}}
	for _, item := range e.Elements {
		bounds = bounds.including(p.expression(item, false))
	}
	return &bounds
}

// Actual calls/defaults remain in generated Go; missing reads still fault.
func (p *intProof) listOperation(e *syntax.Expression, args []intBounds, annotate bool) (intBounds, bool) {
	op := p.listCall(e)
	if op.binding == nil {
		return unknownIntBounds, false
	}
	before := p.getList(op.binding)
	if before == nil {
		return unknownIntBounds, true
	}
	switch op.name {
	case "append":
		length, ok := addIntBounds(before.length, intBounds{1, 1}, false)
		if !ok {
			p.setList(op.binding, nil)
			return unknownIntBounds, true
		}
		next := before.including(args[0])
		next.length = length
		p.setList(op.binding, &next)
	case "length":
		if annotate && before.length.lo == before.length.hi {
			p.g.fn.listLengths[e] = before.length.lo
		}
		return before.length, true
	case "get":
		result := before.elements
		has := before.hasElements
		info := p.g.info(e)
		for i, arg := range info.Arguments {
			if arg.Name != "default" {
				continue
			}
			// Only checked implicit wrapping gives a default value bound. Explicit
			// or unknown Optionals use all Ints; an inactive none.Val is not a value.
			valueInfo := p.g.info(arg.Value)
			if valueInfo == nil || valueInfo.OptionalArgument == nil || p.g.sub(valueInfo.Type).ID != "Int" {
				return unknownIntBounds, true
			}
			if !has {
				result = args[i]
				has = true
			} else {
				result = intBounds{min(result.lo, args[i].lo), max(result.hi, args[i].hi)}
			}
		}
		if has {
			return result, true
		}
	}
	return unknownIntBounds, true
}

type listLoopAppend struct {
	binding *checker.Binding
	value   *syntax.Expression
	top     bool
}

// Summarized traversals reject appends even to other/unknown lists. Each
// expression is visited at most once; statement expressions already reject.
func (p *intProof) containsListAppend(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	if found, ok := p.appendMemo[e]; ok {
		return found
	}
	found := false
	if e.Kind == syntax.KindCall {
		info := p.g.info(e)
		if info != nil && info.Method != nil && info.Method.Native != "" && isStd(info.Method.Receiver, "List") && info.Method.Decl != nil && info.Method.Decl.Name == "append" {
			found = true
		}
	}
	found = p.containsListAppend(e.Left) || p.containsListAppend(e.Right) || found
	for _, a := range e.Args {
		found = p.containsListAppend(a.Value) || found
	}
	for _, item := range e.Elements {
		found = p.containsListAppend(item) || found
	}
	for _, part := range e.Parts {
		found = p.containsListAppend(part.Value) || found
	}
	p.appendMemo[e] = found
	return found
}

// Keep all changed lists unknown until ALL new summaries have been derived.
func (p *intProof) listPostconditions(count *big.Int, appends []listLoopAppend, initial map[*checker.Binding]*listBounds) map[*checker.Binding]*listBounds {
	type additions struct {
		all, unconditional int64
		elements           listBounds
	}
	changes := map[*checker.Binding]*additions{}
	for _, a := range appends {
		d := changes[a.binding]
		if d == nil {
			d = &additions{}
			changes[a.binding] = d
		}
		d.all++
		if a.top {
			d.unconditional++
		}
		d.elements = d.elements.including(p.expression(a.value, false))
	}
	post := map[*checker.Binding]*listBounds{}
	for b, d := range changes {
		old := initial[b]
		if old == nil {
			continue
		}
		lo := new(big.Int).Mul(count, big.NewInt(d.unconditional))
		hi := new(big.Int).Mul(count, big.NewInt(d.all))
		lo.Add(lo, big.NewInt(old.length.lo))
		hi.Add(hi, big.NewInt(old.length.hi))
		if !lo.IsInt64() || !hi.IsInt64() {
			continue
		}
		next := *old
		next.length = intBounds{lo.Int64(), hi.Int64()}
		if d.elements.hasElements {
			next = next.including(d.elements.elements)
		}
		post[b] = &next
	}
	return post
}

func (p *intProof) traversal(s *syntax.Statement) bool {
	if s.Value == nil || s.Value.Kind != syntax.KindName {
		return false
	}
	binding := p.g.info(s.Value).Binding
	if !p.closedList(binding) {
		return false
	}
	before := p.getList(binding)
	if before == nil {
		return false
	}
	var writes []intLoopWrite
	var appends []listLoopAppend
	if !p.loopWrites(s.Body, true, &writes, &appends, true) {
		return false
	}
	elements := unknownIntBounds
	if before.hasElements {
		elements = before.elements
	}
	p.boundedBody(s.Body, big.NewInt(before.length.hi), p.g.program.LoopBinding(s), elements, intBounds{}, writes, appends)
	if before.length.lo >= 256 {
		p.g.fn.rangeChunks[s] = true
	}
	return true
}
