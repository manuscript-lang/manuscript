package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// An immutable local produced by a typed call or accessor keeps its typed
// Result[T]/Option[T] when every use is a match scrutinee or native presence
// flag in the declaring function. Other uses and captures keep it boxed.
type altUses struct {
	names, scrutinees, flags, calls int
	captured                        bool
	callSites                       []*syntax.Expression
}

// planAltLets counts name uses, representation-safe consumers and captures.
func (g *generator) planAltLets() {
	g.altUses = map[*checker.Binding]*altUses{}
	uses := func(b *checker.Binding) *altUses {
		if g.altUses[b] == nil {
			g.altUses[b] = &altUses{}
		}
		return g.altUses[b]
	}
	nodes := syntax.Nodes{Expression: func(e *syntax.Expression) {
		info := g.info(e)
		if info == nil {
			return
		}
		for _, b := range info.Captures {
			uses(b).captured = true
		}
		if e.Kind == syntax.KindName && info.Binding != nil && info.Method == nil {
			uses(info.Binding).names++
		}
		if e.Kind == syntax.KindMember && info.Method != nil && info.Method.Accessor && e.Left != nil && e.Left.Kind == syntax.KindName {
			switch info.Method.Native {
			case "optional/is_some", "optional/is_none", "result/is_ok", "result/is_error":
				if b := g.info(e.Left).Binding; b != nil {
					uses(b).flags++
				}
			}
		}
		if e.Kind == syntax.KindCall && e.Left != nil && e.Left.Kind == syntax.KindName {
			if callee := g.info(e.Left); callee != nil && callee.Binding != nil {
				u := uses(callee.Binding)
				u.calls++
				u.callSites = append(u.callSites, e)
			}
		}
		if e.Kind == syntax.KindMatch && e.Left != nil && e.Left.Kind == syntax.KindName {
			if b := g.info(e.Left).Binding; b != nil {
				uses(b).scrutinees++
			}
		}
	}}
	for _, module := range g.program.Modules {
		nodes.Module(module)
	}
}

// altLet keeps an eligible immutable alternative local in its typed form.
func (g *generator) altLet(s *syntax.Statement) []ast.Stmt {
	if s.Pattern.Kind != syntax.KindName || (s.Value.Kind != syntax.KindCall && s.Value.Kind != syntax.KindMember) {
		return nil
	}
	b := g.program.PatternBinding(s.Pattern)
	u := g.altUses[b]
	if b == nil || b.Mutable || u == nil || u.captured || u.names != u.scrutinees+u.flags || u.names == 0 {
		return nil
	}
	value, direct := g.typedDirectCall(s.Value)
	if value == nil || direct.shape == nil {
		return nil
	}
	if g.altLocals == nil {
		g.altLocals = map[*checker.Binding]*altShape{}
	}
	g.altLocals[b] = direct.shape
	return []ast.Stmt{&ast.DeclStmt{Decl: variable(b.ID, direct.shape.typeExpr(), value)}, discard(ident(b.ID))}
}

// altLocalOf is the typed shape of the local a match scrutinee names, or nil.
func (g *generator) altLocalOf(e *syntax.Expression) (*checker.Binding, *altShape) {
	if e.Kind != syntax.KindName {
		return nil, nil
	}
	info := g.info(e)
	if info == nil || info.Binding == nil || g.captures[info.Binding] != "" {
		return nil, nil
	}
	return info.Binding, g.altLocals[info.Binding]
}
