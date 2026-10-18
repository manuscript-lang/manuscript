package lower

import (
	"math"
	"math/big"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// intBounds is a closed interval. Unknown values span the entire native Int.
// Proof arithmetic uses big.Int: an overflowing proof is never a runtime proof.
type intBounds struct{ lo, hi int64 }

var unknownIntBounds = intBounds{math.MinInt64, math.MaxInt64}

func addIntBounds(a, b intBounds, subtract bool) (intBounds, bool) {
	lo, hi := new(big.Int), new(big.Int)
	if subtract {
		lo.Sub(big.NewInt(a.lo), big.NewInt(b.hi))
		hi.Sub(big.NewInt(a.hi), big.NewInt(b.lo))
	} else {
		lo.Add(big.NewInt(a.lo), big.NewInt(b.lo))
		hi.Add(big.NewInt(a.hi), big.NewInt(b.hi))
	}
	if !lo.IsInt64() || !hi.IsInt64() {
		return unknownIntBounds, false
	}
	return intBounds{lo.Int64(), hi.Int64()}, true
}

// Every corner of a bilinear product must fit. Exact products prevent the
// compiler's own Int overflow from turning a rejected bound into a proof.
func multiplyIntBounds(a, b intBounds) (intBounds, bool) {
	result := intBounds{math.MaxInt64, math.MinInt64}
	for _, x := range []int64{a.lo, a.hi} {
		for _, y := range []int64{b.lo, b.hi} {
			product := new(big.Int).Mul(big.NewInt(x), big.NewInt(y))
			if !product.IsInt64() {
				return unknownIntBounds, false
			}
			value := product.Int64()
			result.lo = min(result.lo, value)
			result.hi = max(result.hi, value)
		}
	}
	return result, true
}

type intFact struct {
	bounds intBounds
	epoch  uint64
	list   *listBounds
}
type intUndo struct {
	binding *checker.Binding
	old     intFact
	had     bool
}
type intProof struct {
	g          *gen
	facts      map[*checker.Binding]intFact
	journal    []intUndo
	epoch      uint64
	serial     uint64
	hazards    map[*syntax.Expression]bool
	inspected  map[*syntax.Expression]bool
	appendMemo map[*syntax.Expression]bool
}

func (g *gen) proveIntArithmetic(body []*syntax.Statement) {
	if g.options.PreserveBindings || g.options.Locals != nil {
		return
	}
	p := &intProof{g: g, facts: map[*checker.Binding]intFact{}, epoch: 1, serial: 1,
		hazards: map[*syntax.Expression]bool{}, inspected: map[*syntax.Expression]bool{}, appendMemo: map[*syntax.Expression]bool{}}
	g.fn.safeInt = map[*syntax.Expression]bool{}
	g.fn.listLengths = map[*syntax.Expression]int64{}
	g.fn.counterChunks = map[*syntax.Statement]*counterChunk{}
	g.fn.recordUpdates = map[*syntax.Expression]*localRecordCall{}
	p.body(body)
}

func (p *intProof) get(b *checker.Binding) intBounds {
	if b == nil || p.g.sub(b.Type).ID != "Int" {
		return unknownIntBounds
	}
	if f, ok := p.facts[b]; ok && f.epoch == p.epoch && f.list == nil {
		return f.bounds
	}
	return unknownIntBounds
}
func (p *intProof) set(b *checker.Binding, bounds intBounds) {
	if b == nil || p.g.sub(b.Type).ID != "Int" {
		return
	}
	old, had := p.facts[b]
	p.journal = append(p.journal, intUndo{b, old, had})
	p.facts[b] = intFact{bounds: bounds, epoch: p.epoch}
}
func (p *intProof) forget() { p.serial++; p.epoch = p.serial }
func (p *intProof) restore(mark int, epoch uint64) {
	for i := len(p.journal) - 1; i >= mark; i-- {
		u := p.journal[i]
		if u.had {
			p.facts[u.binding] = u.old
		} else {
			delete(p.facts, u.binding)
		}
	}
	p.journal = p.journal[:mark]
	p.epoch = epoch
}

// Nested statement expressions can reassign locals. This first proof does not
// transfer facts through them. Callable bodies are analyzed independently and
// inherit no facts, including facts about snapshot captures.
func (p *intProof) hazardous(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	if p.inspected[e] {
		return p.hazards[e]
	}
	p.inspected[e] = true
	hazard := e.Kind == syntax.KindMatch || e.Kind == syntax.KindLambda || len(e.Body) != 0 || len(e.Arms) != 0
	if !hazard {
		hazard = p.hazardous(e.Left) || p.hazardous(e.Right)
		for _, a := range e.Args {
			hazard = p.hazardous(a.Value) || hazard
		}
		for _, item := range e.Elements {
			hazard = p.hazardous(item) || hazard
		}
		for _, part := range e.Parts {
			hazard = p.hazardous(part.Value) || hazard
		}
	}
	p.hazards[e] = hazard
	return hazard
}

func (p *intProof) literal(e *syntax.Expression) (int64, bool) {
	if e == nil || p.g.info(e) == nil || p.g.sub(p.g.info(e).Type).ID != "Int" {
		return 0, false
	}
	text := e.Text
	if e.Kind == syntax.KindUnary && e.Text == "-" && e.Right.Kind == syntax.KindNumber {
		text = "-" + e.Right.Text
	} else if e.Kind != syntax.KindNumber {
		return 0, false
	}
	n, err := strconv.ParseInt(text, 0, 64)
	return n, err == nil
}

func (p *intProof) expression(e *syntax.Expression, annotate bool) intBounds {
	if e == nil {
		return unknownIntBounds
	}
	if p.hazardous(e) {
		p.forget()
		return unknownIntBounds
	}
	if n, ok := p.literal(e); ok {
		return intBounds{n, n}
	}
	left, right := p.expression(e.Left, annotate), p.expression(e.Right, annotate)
	args := make([]intBounds, len(e.Args))
	for i, a := range e.Args {
		args[i] = p.expression(a.Value, annotate)
	}
	for _, item := range e.Elements {
		p.expression(item, annotate)
	}
	for _, part := range e.Parts {
		p.expression(part.Value, annotate)
	}
	if bounds, ok := p.listOperation(e, args, annotate); ok {
		return bounds
	}
	if bounds, ok := p.recordOperation(e, args, annotate); ok {
		return bounds
	}
	info := p.g.info(e)
	if info == nil || p.g.sub(info.Type).ID != "Int" {
		return unknownIntBounds
	}
	switch e.Kind {
	case syntax.KindName:
		return p.get(info.Binding)
	case syntax.KindBinary:
		if e.Text == "+" || e.Text == "-" {
			if bounds, ok := addIntBounds(left, right, e.Text == "-"); ok {
				if annotate {
					p.g.fn.safeInt[e] = true
				}
				return bounds
			}
		}
		if e.Text == "*" {
			if bounds, ok := multiplyIntBounds(left, right); ok {
				if annotate {
					p.g.fn.safeInt[e] = true
				}
				return bounds
			}
		}
	case syntax.KindCall:
		// Infer only the return interval; preserve the ordinary call and its
		// evaluation. Checked parameter identity excludes shadowing/defaults.
		callee := p.g.info(e.Left)
		if len(args) == 1 && callee != nil && callee.Symbol != nil && callee.Symbol.Native == "" {
			d := callee.Symbol.Decl
			if d != nil && len(d.Params) == 1 && d.Params[0].Default == nil && len(d.Body) == 1 &&
				d.Body[0].Kind == syntax.KindReturn && d.Body[0].Value.Kind == syntax.KindName {
				bindings := p.g.program.ParameterBindings(d)
				ret := p.g.info(d.Body[0].Value)
				if len(bindings) == 1 && ret != nil && ret.Binding == bindings[0] {
					return args[0]
				}
			}
		}
	}
	return unknownIntBounds
}

func (p *intProof) target(s *syntax.Statement) *checker.Binding {
	if s.Kind == syntax.KindBind && s.Pattern.Kind == syntax.KindName {
		return p.g.program.PatternBinding(s.Pattern)
	}
	if s.Kind == syntax.KindAssign && s.Target == nil {
		return p.g.program.AssignedBinding(s.Value)
	}
	return nil
}

func (p *intProof) body(body []*syntax.Statement) {
	for _, s := range body {
		switch s.Kind {
		case syntax.KindWhile, syntax.KindFor:
			if s.Kind == syntax.KindWhile && p.loop(s) || s.Kind == syntax.KindFor && p.traversal(s) {
				continue
			}
			p.forget()
			p.expression(s.Value, true)
			p.body(s.Body)
			p.forget()
		case syntax.KindIf:
			p.expression(s.Value, true)
			mark, epoch := len(p.journal), p.epoch
			p.successBinding(s)
			p.body(s.Body)
			p.restore(mark, epoch)
			p.body(s.Else)
			p.restore(mark, epoch)
			p.forget()
		case syntax.KindWith:
			p.expression(s.Value, true)
			p.body(s.Body)
			p.forget()
		default:
			// Target and value can both contain statement expressions. Discard
			// all entering facts before either when that is possible.
			if p.hazardous(s.Target) || p.hazardous(s.Value) {
				p.forget()
			}
			p.expression(s.Target, true)
			bounds := p.expression(s.Value, true)
			b := p.target(s)
			p.set(b, bounds)
			if s.Kind == syntax.KindBind && p.closedList(b) {
				p.setList(b, p.literalList(s.Value))
			}
			if s.Kind == syntax.KindBind && p.recordField(b) != "" {
				p.setCell(b, p.expression(p.g.info(s.Value).Arguments[0].Value, false))
			}
		}
	}
}

type intLoopWrite struct {
	binding *checker.Binding
	value   *syntax.Expression
	top     bool
}

// A summary scans only this loop's statements. It stops at nested loops, so
// deeply nested source never causes repeated scans of nested subtrees.
func (p *intProof) loopWrites(body []*syntax.Statement, top bool, writes *[]intLoopWrite, appends *[]listLoopAppend, forbidAppend bool) bool {
	for _, s := range body {
		if p.hazardous(s.Target) || p.hazardous(s.Value) {
			return false
		}
		if forbidAppend && (p.containsListAppend(s.Target) || p.containsListAppend(s.Value)) {
			return false
		}
		if s.Kind == syntax.KindCall {
			if op := p.recordCall(s.Value); op != nil {
				*writes = append(*writes, intLoopWrite{op.binding, s.Value, top})
			}
			if op := p.listCall(s.Value); op.name == "append" {
				*appends = append(*appends, listLoopAppend{op.binding, s.Value.Args[0].Value, top})
			}
		}
		switch s.Kind {
		case syntax.KindWhile, syntax.KindFor, syntax.KindContinue, syntax.KindBreak, syntax.KindReturn, syntax.KindWith:
			return false
		case syntax.KindAssign:
			if b := p.target(s); b != nil {
				*writes = append(*writes, intLoopWrite{b, s.Value, top})
			}
		case syntax.KindIf:
			if !p.loopWrites(s.Body, false, writes, appends, forbidAppend) || !p.loopWrites(s.Else, false, writes, appends, forbidAppend) {
				return false
			}
		}
	}
	return true
}

func (p *intProof) loop(s *syntax.Statement) bool {
	cond := s.Value
	if cond == nil || cond.Kind != syntax.KindBinary || (cond.Text != "<" && cond.Text != ">") ||
		cond.Left.Kind != syntax.KindName {
		return false
	}
	counter := p.g.info(cond.Left).Binding
	start := p.get(counter)
	limit, ok := p.literal(cond.Right)
	if counter == nil || p.g.sub(counter.Type).ID != "Int" || start.lo != start.hi || !ok {
		return false
	}
	var writes []intLoopWrite
	var appends []listLoopAppend
	if !p.loopWrites(s.Body, true, &writes, &appends, false) {
		return false
	}
	step, last := "+", limit
	if cond.Text == ">" {
		step = "-"
	}
	counterWrites := 0
	for _, w := range writes {
		if w.binding != counter {
			continue
		}
		counterWrites++
		v := w.value
		if !w.top || v.Kind != syntax.KindBinary || v.Text != step || v.Left.Kind != syntax.KindName ||
			p.g.info(v.Left).Binding != counter {
			return false
		}
		if n, ok := p.literal(v.Right); !ok || n != 1 {
			return false
		}
	}
	if counterWrites != 1 {
		return false
	}
	count := new(big.Int)
	if step == "+" && start.lo < limit {
		count.Sub(big.NewInt(limit), big.NewInt(start.lo))
	} else if step == "-" && start.lo > limit {
		count.Sub(big.NewInt(start.lo), big.NewInt(limit))
	} else {
		last = start.lo
	}
	if !count.IsInt64() {
		return false
	}
	counterBounds := intBounds{min(start.lo, last), max(start.hi, last)}
	p.boundedBody(s.Body, count, counter, counterBounds, intBounds{last, last}, writes, appends)
	if step == "+" && count.Int64() >= 256 {
		p.chunk(s, counter, limit, counterBounds)
	}
	return true
}

func (p *intProof) boundedBody(body []*syntax.Statement, count *big.Int, counter *checker.Binding, counterBounds, counterPost intBounds, writes []intLoopWrite, appends []listLoopAppend) {
	mark, epoch := len(p.journal), p.epoch
	initial := map[*checker.Binding]intBounds{}
	for _, w := range writes {
		initial[w.binding] = p.getCell(w.binding)
	}
	// Invalidate ALL carries before deriving deltas. A peer accumulator's
	// initial value is not an invariant, even when its own proof fails.
	for b := range initial {
		p.setCell(b, unknownIntBounds)
	}
	initialLists := map[*checker.Binding]*listBounds{}
	for _, a := range appends {
		initialLists[a.binding] = p.getList(a.binding)
	}
	for b := range initialLists {
		p.setList(b, nil)
	}
	p.set(counter, counterBounds)
	type contributions struct {
		negative, positive big.Int
		valid              bool
	}
	deltas := map[*checker.Binding]*contributions{}
	writeByValue := map[*syntax.Expression]intLoopWrite{}
	for _, w := range writes {
		writeByValue[w.value] = w
	}
	p.loopDeltas(body, writeByValue, func(w intLoopWrite) {
		b, v := w.binding, w.value
		if b == counter {
			return
		}
		d := deltas[b]
		if d == nil {
			d = &contributions{valid: true}
			deltas[b] = d
		}
		var delta intBounds
		subtract := false
		if op := p.recordCall(v); op != nil {
			delta = p.expression(v.Args[0].Value, false)
			subtract = op.operator == "-"
		} else if v.Kind != syntax.KindBinary || (v.Text != "+" && v.Text != "-") ||
			v.Left.Kind != syntax.KindName || p.g.info(v.Left).Binding != b {
			d.valid = false
			return
		} else {
			delta = p.expression(v.Right, false)
			subtract = v.Text == "-"
		}
		lo, hi := big.NewInt(delta.lo), big.NewInt(delta.hi)
		if subtract {
			lo, hi = new(big.Int).Neg(hi), new(big.Int).Neg(lo)
		}
		if lo.Sign() < 0 {
			d.negative.Add(&d.negative, lo)
		}
		if hi.Sign() > 0 {
			d.positive.Add(&d.positive, hi)
		}
	})
	post := map[*checker.Binding]intBounds{counter: counterPost}
	for b, d := range deltas {
		if !d.valid {
			continue
		}
		before := initial[b]
		lo := new(big.Int).Mul(count, &d.negative)
		hi := new(big.Int).Mul(count, &d.positive)
		lo.Add(lo, big.NewInt(before.lo))
		hi.Add(hi, big.NewInt(before.hi))
		if lo.IsInt64() && hi.IsInt64() {
			bounds := intBounds{lo.Int64(), hi.Int64()}
			post[b] = bounds
		}
	}
	postLists := p.listPostconditions(count, appends, initialLists)
	// Install invariants only after every scalar/list delta has been derived.
	for b, bounds := range post {
		if b != counter {
			p.setCell(b, bounds)
		}
	}
	for b, bounds := range postLists {
		invariant := *bounds
		invariant.length.lo = initialLists[b].length.lo
		p.setList(b, &invariant)
	}
	p.body(body)
	p.restore(mark, epoch)
	for b := range initial {
		bounds, ok := post[b]
		if !ok {
			bounds = unknownIntBounds
		}
		p.setCell(b, bounds)
	}
	for b := range initialLists {
		p.setList(b, postLists[b])
	}
}
