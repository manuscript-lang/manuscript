package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

// Bound repeated source literals to 8064 bytes per selected site.
const maxBuilderFragmentBytes = 128

type builderAppend struct {
	binding  *checker.Binding
	fragment string
}

// Inventory every use, including nested callables. A top-level freeze can only
// follow all append-containing statements; no supported alias can seal earlier.
func (g *gen) closedBuilderAppends(body []*syntax.Statement) map[*syntax.Expression]builderAppend {
	type candidate struct {
		valid          bool
		freeze, append int
	}
	candidates := map[*checker.Binding]*candidate{}
	freezes := map[*syntax.Expression]bool{}
	for _, s := range body {
		if s.Kind == syntax.KindCall || s.Kind == syntax.KindBind || s.Kind == syntax.KindReturn {
			freezes[s.Value] = true
		}
		if s.Kind != syntax.KindBind || s.Mutable || s.Pattern.Kind != syntax.KindName || s.Value == nil || s.Value.Kind != syntax.KindCall || len(s.Value.Args) != 0 {
			continue
		}
		b, info := g.program.PatternBinding(s.Pattern), g.info(s.Value)
		if b != nil && !b.Mutable && info != nil && g.resultPlain(s.Value) && isStd(g.sub(b.Type), "StringBuilder") && isStd(info.Constructor, "StringBuilder") && len(info.Arguments) == 0 {
			candidates[b] = &candidate{valid: true, freeze: len(body), append: -1}
		}
	}
	calls := map[*syntax.Expression]builderAppend{}
	roots := map[*syntax.Expression]bool{}
	for at, s := range body {
		var stack []*syntax.Expression
		depth := 0
		syntax.Visitor{Statement: func(s *syntax.Statement) {
			if s.Kind == syntax.KindCall {
				roots[s.Value] = true
			}
		}, Expression: func(e *syntax.Expression) {
			if e.Kind == syntax.KindLambda {
				depth++
			}
			info := g.info(e)
			if info != nil && info.Binding != nil {
				if c := candidates[info.Binding]; c != nil {
					valid := depth == 0 && e.Kind == syntax.KindName && len(stack) >= 2
					var call *syntax.Expression
					var name string
					if valid {
						member := stack[len(stack)-1]
						call = stack[len(stack)-2]
						m := g.info(member)
						valid = member.Kind == syntax.KindMember && member.Left == e && call.Kind == syntax.KindCall && call.Left == member && g.resultPlain(call) && m != nil && m.Method != nil && m.Method.Native != "" && m.Method.Native != "contract" && !m.Method.Local && isStd(m.Method.Receiver, "StringBuilder") && m.Method.Decl != nil && m.Method.Decl.Name == member.Text
						if valid {
							name = member.Text
						}
					}
					if valid {
						switch name {
						case "append":
							valid = roots[call] && len(call.Args) == 1
							c.append = max(c.append, at)
							if valid && g.resultStringLiteral(call.Args[0].Value) {
								var text strings.Builder
								for _, part := range call.Args[0].Value.Parts {
									text.WriteString(part.Text)
								}
								if text.Len() <= maxBuilderFragmentBytes {
									calls[call] = builderAppend{info.Binding, text.String()}
								}
							}
						case "freeze":
							valid = freezes[call] && len(call.Args) == 0
							c.freeze = min(c.freeze, at)
						default:
							valid = false
						}
					}
					if !valid {
						c.valid = false
					}
				}
			}
			stack = append(stack, e)
		}, LeaveExpression: func(e *syntax.Expression) {
			stack = stack[:len(stack)-1]
			if e.Kind == syntax.KindLambda {
				depth--
			}
		}}.Callable(nil, []*syntax.Statement{s})
	}
	for call, op := range calls {
		c := candidates[op.binding]
		if !c.valid || c.freeze <= c.append {
			delete(calls, call)
		}
	}
	return calls
}
