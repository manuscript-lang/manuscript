package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// localCollectionProof inventories closed collections. Map storage has exclusive
// consumers: an ordinary Map operation must
// never receive the alternate key->value interpretation of its index field.
// Keep this deliberately narrower than general escape analysis.
type localCollectionProof struct {
	builderAppends map[*syntax.Expression]builderAppend
	constructors   map[*syntax.Expression]bool
	calls          map[*syntax.Expression]string
	lists          map[*checker.Binding]bool
	listCalls      map[*syntax.Expression]localListCall
	records        map[*checker.Binding]string
	recordCalls    map[*syntax.Expression]*localRecordCall
}

type localListCall struct {
	binding *checker.Binding
	name    string
}

func (g *gen) proveLocalCollections(params []syntax.Parameter, body []*syntax.Statement) *localCollectionProof {
	if g.options.PreserveBindings || g.options.Locals != nil || g.localImpl {
		return nil
	}
	type candidate struct {
		constructor *syntax.Expression
		kind        string
		depth       int
		valid       bool
		field       string
	}
	candidates := map[*checker.Binding]*candidate{}
	roots := map[*syntax.Expression]bool{}
	iterables := map[*syntax.Expression]bool{}
	depth := 0
	enter := func(e *syntax.Expression) {
		if e.Kind == syntax.KindLambda {
			depth++
		}
	}
	leave := func(e *syntax.Expression) {
		if e.Kind == syntax.KindLambda {
			depth--
		}
	}
	// Include defaults, arms and nested callables once. Lambdas inherit this
	// immutable inventory; they do not rescan increasingly nested subtrees.
	syntax.Visitor{Expression: enter, LeaveExpression: leave, Statement: func(s *syntax.Statement) {
		if s.Kind == syntax.KindFor {
			iterables[s.Value] = true
		}
		if s.Kind == syntax.KindCall {
			roots[s.Value] = true
		}
		if s.Kind != syntax.KindBind || s.Pattern.Kind != syntax.KindName || s.Value == nil {
			return
		}
		b, info := g.program.PatternBinding(s.Pattern), g.info(s.Value)
		if b == nil || info == nil {
			return
		}
		t := g.sub(b.Type)
		kind, field := "", ""
		if isStd(t, "List") && len(t.Args) == 1 && t.Args[0].ID == "Int" && s.Value.Kind == syntax.KindList {
			kind = "List"
		}
		if isStd(t, "Map") && len(t.Args) == 2 && t.Args[0].ID == "Int" && t.Args[1].ID == "Int" &&
			s.Value.Kind == syntax.KindCall && len(s.Value.Args) == 0 && len(info.Arguments) == 0 && isStd(info.Constructor, "Map") && info.Case == "" &&
			g.closedIntMap {
			kind = "Map"
		}
		if len(g.subst) == 0 && t.Kind == "record" && !isStdType(t) && len(t.Args) == 0 && t.Def != nil && len(t.Def.Variables) == 0 && len(t.Def.Fields) == 1 &&
			s.Value.Kind == syntax.KindCall && info.Constructor != nil && checker.TypeKey(g.sub(info.Constructor)) == checker.TypeKey(t) && len(info.Arguments) == 1 && info.Case == "" {
			fields := checker.Fields(t)
			if len(fields) == 1 && fields[0].Type.ID == "Int" {
				if _, ok := (&intProof{g: g}).literal(info.Arguments[0].Value); ok {
					kind, field = "record", fields[0].Name
				}
			}
		}
		if kind != "" {
			candidates[b] = &candidate{constructor: s.Value, kind: kind, depth: depth, valid: true, field: field}
		}

	}}.Callable(params, body)

	type operation struct {
		binding *checker.Binding
		name    string
		record  *localRecordCall
	}
	operations := map[*syntax.Expression]operation{}
	var stack []*syntax.Expression
	syntax.Visitor{Statement: func(s *syntax.Statement) {
		// A `var` candidate rebound to another value is no longer a closed local.
		if s.Kind == syntax.KindAssign && s.Target == nil {
			if c := candidates[g.program.AssignedBinding(s.Value)]; c != nil {
				c.valid = false
			}
		}
	}, Expression: func(e *syntax.Expression) {
		enter(e)
		info := g.info(e)
		if e.Kind == syntax.KindLambda && info != nil {
			for _, capture := range info.Captures {
				if c := candidates[capture]; c != nil {
					c.valid = false
				}
			}
		}
		if info != nil && info.Binding != nil && candidates[info.Binding] != nil {
			c := candidates[info.Binding]
			valid := e.Kind == syntax.KindName && depth == c.depth
			if c.kind == "record" {
				valid = valid && len(stack) >= 1
				if valid {
					member := stack[len(stack)-1]
					memberInfo := g.info(member)
					valid = member.Kind == syntax.KindMember && member.Left == e && memberInfo != nil && !memberInfo.Write
					if valid && memberInfo.Method == nil {
						valid = member.Text == c.field && g.sub(memberInfo.Type).ID == "Int"
					} else if valid && len(stack) >= 2 {
						call := stack[len(stack)-2]
						update := g.localRecordMethod(memberInfo.Method, g.sub(info.Binding.Type), c.field)
						valid = roots[call] && call.Kind == syntax.KindCall && call.Left == member && len(call.Args) == 1 && update != nil
						if valid {
							update.binding = info.Binding
							operations[call] = operation{binding: info.Binding, record: update}
						}
					} else {
						valid = false
					}
				}
				if !valid {
					c.valid = false
				}
				stack = append(stack, e)
				return
			}
			iterable := valid && c.kind == "List" && iterables[e]
			valid = valid && len(stack) >= 2
			var call *syntax.Expression
			var name string
			if valid {
				member := stack[len(stack)-1]
				call = stack[len(stack)-2]
				valid = member.Kind == syntax.KindMember && member.Left == e &&
					call.Kind == syntax.KindCall && call.Left == member
				if valid {
					callee := g.info(member)
					valid = callee != nil && callee.Method != nil && callee.Method.Native != "" &&
						callee.Method.Native != "contract" && !callee.Method.Local && isStd(callee.Method.Receiver, c.kind) &&
						callee.Method.Decl != nil && callee.Method.Decl.Name == member.Text
					if valid {
						name = member.Text
						switch name {
						case "add":
							valid = c.kind == "Map" && roots[call] && len(call.Args) == 2
						case "append":
							valid = c.kind == "List" && roots[call] && len(call.Args) == 1
						case "get":
							valid = len(call.Args) == 1 || c.kind == "List" && len(call.Args) == 2
						case "contains":
							valid = c.kind == "Map" && len(call.Args) == 1
						case "length":
							valid = len(call.Args) == 0
						default:
							valid = false
						}
					}
				}
			}
			if iterable {
				valid = true
			}
			if !valid {
				c.valid = false
			} else if !iterable {
				operations[call] = operation{binding: info.Binding, name: name}
			}
		}
		stack = append(stack, e)
	}, LeaveExpression: func(e *syntax.Expression) {
		stack = stack[:len(stack)-1]
		leave(e)
	}}.Callable(params, body)
	proof := &localCollectionProof{constructors: map[*syntax.Expression]bool{}, calls: map[*syntax.Expression]string{}, lists: map[*checker.Binding]bool{}, listCalls: map[*syntax.Expression]localListCall{}, records: map[*checker.Binding]string{}, recordCalls: map[*syntax.Expression]*localRecordCall{}}
	for b, c := range candidates {
		if !c.valid {
			continue
		}
		if c.kind == "Map" {
			proof.constructors[c.constructor] = true
		} else if c.kind == "record" {
			proof.records[b] = c.field
		} else {
			proof.lists[b] = true
		}
	}
	for call, op := range operations {
		if candidates[op.binding].valid {
			if candidates[op.binding].kind == "Map" {
				proof.calls[call] = op.name
			} else if candidates[op.binding].kind == "record" {
				proof.recordCalls[call] = op.record
			} else {
				proof.listCalls[call] = localListCall{op.binding, op.name}
			}
		}
	}
	proof.builderAppends = g.closedBuilderAppends(body)
	return proof
}
