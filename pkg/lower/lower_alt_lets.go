package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A `let` bound to a typed direct call that returns a Result or Optional keeps
// the typed Result[T]/Option[T] when the name is only ever the scrutinee of a
// match in the function that declares it. It is then neither boxed into an
// Alternative nor tested through Tag/Payload assertions. Any other use of the
// name, and any capture of it, keeps the boxed form.
type altUses struct {
	names, scrutinees int
	captured          bool
}

// planAltLets counts, for every binding, its name uses, its uses as a match
// scrutinee and whether a closure captures it.
func (g *generator) planAltLets() {
	g.altUses = map[*checker.Binding]*altUses{}
	uses := func(b *checker.Binding) *altUses {
		if g.altUses[b] == nil {
			g.altUses[b] = &altUses{}
		}
		return g.altUses[b]
	}
	nodes := syntax.Nodes{Expression: func(e *syntax.Expression) {
		info := g.program.Info(e)
		if info == nil {
			return
		}
		for _, b := range info.Captures {
			uses(b).captured = true
		}
		if e.Kind == syntax.KindName && info.Binding != nil && info.Method == nil {
			uses(info.Binding).names++
		}
		if e.Kind == syntax.KindMatch && e.Left != nil && e.Left.Kind == syntax.KindName {
			if b := g.program.Info(e.Left).Binding; b != nil {
				uses(b).scrutinees++
			}
		}
	}}
	for _, module := range g.program.Modules {
		nodes.Module(module)
	}
}

// altLet lowers `let name = call(...)` as a typed variable, or returns nil
// when the binding does not qualify.
func (g *generator) altLet(s *syntax.Statement) []ast.Stmt {
	if s.Pattern.Kind != syntax.KindName || s.Value.Kind != syntax.KindCall {
		return nil
	}
	b := g.program.PatternBinding(s.Pattern)
	u := g.altUses[b]
	if b == nil || b.Mutable || u == nil || u.captured || u.names != u.scrutinees || u.names == 0 {
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
	info := g.program.Info(e)
	if info == nil || info.Binding == nil || g.captures[info.Binding] != "" {
		return nil, nil
	}
	return info.Binding, g.altLocals[info.Binding]
}
