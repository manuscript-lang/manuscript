package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// One immutable plan per callee and approved call ID. No general function's
// checked facts are changed; each bounded clone copies its own annotations.
type matchIntPlan struct {
	symbol        *checker.Symbol
	schema        *matchIntSchema
	arms          []matchIntArm
	input, output intBounds
	hasInput      bool
	safe          map[*syntax.Expression]bool
	gets          map[*syntax.Expression]int64
}
type matchIntSchema struct {
	typ   *checker.Type
	cases map[string]bool
}
type matchIntArm struct {
	payload *checker.Binding
	value   *syntax.Expression
}

func (g *gen) matchIntPlans() map[*syntax.Expression]*matchIntPlan {
	calls := map[*syntax.Expression]*matchIntPlan{}
	if g.program == nil || g.localImpl {
		return calls
	}
	schemas := map[string]*matchIntSchema{}
	plans := map[*syntax.Declaration]*matchIntPlan{}
	// Index and validate each nominal case schema and fixed callee once.
	for _, module := range g.program.Modules {
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindFn || d.Receiver != nil || len(d.TypeParams) != 0 || len(d.Params) != 1 || d.Params[0].Default != nil || len(d.Body) != 3 {
				continue
			}
			symbol := g.program.Symbol(module.File, d.Name)
			if symbol == nil || symbol.Native != "" || len(symbol.Variables) != 0 || symbol.Type.Result == nil || symbol.Type.Result.ID != "Int" || defaulted(symbol.Type, 0) {
				continue
			}
			params := g.program.ParameterBindings(d)
			if len(params) != 1 || params[0].Mutable {
				continue
			}
			t := params[0].Type
			schema, seen := schemas[t.ID]
			if !seen {
				schema = g.matchIntSchema(t)
				schemas[t.ID] = schema
			}
			if schema == nil {
				continue
			}
			bind, match, ret := d.Body[0], d.Body[1], d.Body[2]
			if bind.Kind != syntax.KindBind || !bind.Mutable || bind.Pattern.Kind != syntax.KindName || match.Kind != syntax.KindCall || match.Value == nil || match.Value.Kind != syntax.KindMatch || ret.Kind != syntax.KindReturn {
				continue
			}
			out := g.program.PatternBinding(bind.Pattern)
			if out == nil || out.Type.ID != "Int" || !g.resultParameter(ret.Value, out) || !g.resultParameter(match.Value.Left, params[0]) || !g.resultPlain(match.Value) {
				continue
			}
			if _, ok := (&intProof{g: g}).literal(bind.Value); !ok {
				continue
			}
			if len(match.Value.Arms) != len(schema.cases) {
				continue
			}
			plan := &matchIntPlan{symbol: symbol, schema: schema}
			covered := map[string]bool{}
			for i := range match.Value.Arms {
				a := &match.Value.Arms[i]
				payload := g.program.ArmBindingsFor(a)
				if a.Path == nil || !schema.cases[a.Path.Text] || covered[a.Path.Text] || len(payload) != 1 || payload[0] == nil || payload[0].Mutable || payload[0].Type.ID != "Int" || len(a.Names) != 1 || a.Value != nil || len(a.Body) != 1 {
					break
				}
				assignment := a.Body[0]
				if assignment.Kind != syntax.KindAssign || assignment.Target != nil || assignment.Compound != "" || g.program.AssignedBinding(assignment.Value) != out || !g.matchIntValue(assignment.Value, payload[0]) {
					break
				}
				covered[a.Path.Text] = true
				plan.arms = append(plan.arms, matchIntArm{payload[0], assignment.Value})
			}
			if len(covered) == len(schema.cases) {
				plans[d] = plan
			}
		}
	}
	if len(plans) == 0 {
		return calls
	}
	// Each caller's whole ownership/call inventory is linear. Union only approved
	// call inputs, not unknown uses of the same general source function.
	for _, module := range g.program.Modules {
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindFn && d.Receiver == nil && len(d.TypeParams) == 0 {
				g.matchIntInputs(d, schemas, plans, calls)
			}
		}
	}
	// Evaluate <=8 single-operation arms once with the final uniform union.
	for _, plan := range plans {
		if !plan.hasInput {
			continue
		}
		plan.safe = map[*syntax.Expression]bool{}
		valid := true
		for i, arm := range plan.arms {
			bounds, ok := g.matchIntValueBounds(arm.value, arm.payload, plan.input, plan.safe)
			if !ok {
				valid = false
				break
			}
			if i == 0 {
				plan.output = bounds
			} else {
				plan.output = intBounds{min(plan.output.lo, bounds.lo), max(plan.output.hi, bounds.hi)}
			}
		}
		if !valid || len(plan.safe) == 0 {
			plan.safe = nil
		}
	}
	for e, plan := range calls {
		if plan.safe == nil {
			delete(calls, e)
		}
	}
	return calls
}

func (g *gen) matchIntSchema(t *checker.Type) *matchIntSchema {
	if t == nil || t.Kind != "alternative" || isStdType(t) || len(t.Args) != 0 || t.Def == nil || len(t.Def.Variables) != 0 || t.Def.Symbol == nil || t.Def.Symbol.Native != "" || t.Def.Symbol.Decl == nil {
		return nil
	}
	definition := t.Def.Symbol.Decl
	cases := checker.Cases(t)
	if len(cases) == 0 || len(cases) > 8 || len(definition.Cases) != len(cases) {
		return nil
	}
	schema := &matchIntSchema{typ: t, cases: map[string]bool{}}
	for i, c := range cases {
		source := definition.Cases[i]
		if len(c.Fields) != 1 || c.Fields[0].Type.ID != "Int" || source.Name != c.Name || len(source.Fields) != 1 || source.Fields[0].Default != nil {
			return nil
		}
		schema.cases[c.Name] = true
	}
	return schema
}

func (g *gen) matchIntLeaf(e *syntax.Expression, payload *checker.Binding) bool {
	if g.resultParameter(e, payload) {
		return true
	}
	_, ok := (&intProof{g: g}).literal(e)
	return ok && g.resultPlain(e)
}
func (g *gen) matchIntValue(e *syntax.Expression, payload *checker.Binding) bool {
	if g.matchIntLeaf(e, payload) {
		return true
	}
	return e != nil && g.resultPlain(e) && g.info(e).Type.ID == "Int" && g.info(e).Method == nil && e.Kind == syntax.KindBinary && (e.Text == "+" || e.Text == "-" || e.Text == "*") && g.matchIntLeaf(e.Left, payload) && g.matchIntLeaf(e.Right, payload)
}
func (g *gen) matchIntValueBounds(e *syntax.Expression, payload *checker.Binding, input intBounds, safe map[*syntax.Expression]bool) (intBounds, bool) {
	leaf := func(e *syntax.Expression) intBounds {
		if g.resultParameter(e, payload) {
			return input
		}
		n, _ := (&intProof{g: g}).literal(e)
		return intBounds{n, n}
	}
	if g.matchIntLeaf(e, payload) {
		return leaf(e), true
	}
	a, b := leaf(e.Left), leaf(e.Right)
	var bounds intBounds
	var ok bool
	if e.Text == "*" {
		bounds, ok = multiplyIntBounds(a, b)
	} else {
		bounds, ok = addIntBounds(a, b, e.Text == "-")
	}
	if ok {
		safe[e] = true
	}
	return bounds, ok
}

type matchIntList struct {
	length int64
	schema *matchIntSchema
	bounds intBounds
	valid  bool
}

func (g *gen) matchIntInputs(d *syntax.Declaration, schemas map[string]*matchIntSchema, plans map[*syntax.Declaration]*matchIntPlan, calls map[*syntax.Expression]*matchIntPlan) {
	lists := map[*checker.Binding]*matchIntList{}
	for _, s := range d.Body {
		if s.Kind != syntax.KindBind || s.Mutable || s.Pattern.Kind != syntax.KindName || s.Value == nil || s.Value.Kind != syntax.KindList || len(s.Value.Elements) == 0 {
			continue
		}
		b := g.program.PatternBinding(s.Pattern)
		if b == nil || b.Mutable || g.capturedBindings[b] || !isStd(b.Type, "List") || len(b.Type.Args) != 1 {
			continue
		}
		schema := schemas[b.Type.Args[0].ID]
		if schema == nil {
			continue
		}
		candidate := &matchIntList{schema: schema, valid: true, length: int64(len(s.Value.Elements))}
		for i, e := range s.Value.Elements {
			info := g.info(e)
			if e.Kind != syntax.KindCall || len(e.Args) != 1 || info == nil || !g.resultPlain(e) || info.Constructor == nil || info.Constructor.ID != schema.typ.ID || info.Type.ID != schema.typ.ID || len(info.TypeArgs) != 0 || len(info.Arguments) != 1 || !schema.cases[info.Case] || !g.resultPlain(e.Args[0].Value) {
				candidate.valid = false
				break
			}
			n, ok := (&intProof{g: g}).literal(e.Args[0].Value)
			if !ok {
				candidate.valid = false
				break
			}
			if i == 0 {
				candidate.bounds = intBounds{n, n}
			} else {
				candidate.bounds = intBounds{min(candidate.bounds.lo, n), max(candidate.bounds.hi, n)}
			}
		}
		lists[b] = candidate
	}
	if len(lists) == 0 {
		return
	}
	gets := map[*syntax.Expression]*matchIntList{}
	pending := map[*syntax.Expression]*matchIntPlan{}
	var stack []*syntax.Expression
	depth := 0
	syntax.Visitor{Expression: func(e *syntax.Expression) {
		if e.Kind == syntax.KindLambda {
			depth++
		}
		info := g.info(e)
		if e.Kind == syntax.KindCall && depth == 0 && len(e.Args) == 1 && e.Left.Kind == syntax.KindName && info != nil && info.Symbol != nil && g.resultPlain(e) && len(info.TypeArgs) == 0 {
			callee := g.info(e.Left)
			if plan := plans[info.Symbol.Decl]; plan != nil && callee != nil && callee.Binding == nil && callee.Symbol == info.Symbol && g.resultPlain(e.Left) && info.Type.ID == "Int" {
				pending[e] = plan
			}
		}
		if info != nil && info.Binding != nil {
			if list := lists[info.Binding]; list != nil {
				valid := depth == 0 && e.Kind == syntax.KindName && len(stack) >= 2
				var call *syntax.Expression
				var name string
				if valid {
					member := stack[len(stack)-1]
					call = stack[len(stack)-2]
					m := g.info(member)
					valid = member.Kind == syntax.KindMember && member.Left == e && call.Kind == syntax.KindCall && call.Left == member && g.resultPlain(call) && m != nil && m.Method != nil && m.Method.Native != "" && m.Method.Native != "contract" && !m.Method.Local && isStd(m.Method.Receiver, "List") && m.Method.Decl != nil && m.Method.Decl.Name == member.Text
					if valid {
						name = member.Text
						valid = (name == "get" && len(call.Args) == 1) || (name == "length" && len(call.Args) == 0)
					}
				}
				if !valid {
					list.valid = false
				} else if name == "get" && g.info(call).Type.ID == list.schema.typ.ID {
					gets[call] = list
				}
			}
		}
		stack = append(stack, e)
	}, LeaveExpression: func(e *syntax.Expression) {
		stack = stack[:len(stack)-1]
		if e.Kind == syntax.KindLambda {
			depth--
		}
	}}.Callable(d.Params, d.Body)
	for call, plan := range pending {
		list := gets[call.Args[0].Value]
		if list == nil || !list.valid || list.schema != plan.schema {
			continue
		}
		calls[call] = plan
		if plan.gets == nil {
			plan.gets = map[*syntax.Expression]int64{}
		}
		plan.gets[call.Args[0].Value] = list.length
		if !plan.hasInput {
			plan.input = list.bounds
			plan.hasInput = true
		} else {
			plan.input = intBounds{min(plan.input.lo, list.bounds.lo), max(plan.input.hi, list.bounds.hi)}
		}
	}
}

func (g *gen) boundedMatch(e *syntax.Expression) *matchIntPlan {
	if g.options.PreserveBindings || g.options.Locals != nil {
		return nil
	}
	return g.matchBounds[e]
}
func (g *gen) boundedMatchFunction(plan *matchIntPlan) *funcDecl {
	original := g.function(plan.symbol, nil) // Keep the general function and registration.
	key := original.key + "#bounded-match"
	g.mu.Lock()
	existing := g.funcs[key]
	g.mu.Unlock()
	if existing != nil {
		g.touch(&existing.node)
		return existing
	}
	f := &funcDecl{key: key, name: g.derivedOrClaim(original.name+"_bounded", key, true), module: original.module, scope: original.scope, symbol: original.symbol, decl: original.decl, typ: original.typ, subst: original.subst, bounded: plan}
	f.fn = f
	return g.intern(f)
}
