package lower

import (
	"go/ast"
	"go/token"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// effects summarizes what evaluating a Go expression can observe or change.
type effects struct {
	calls bool // runs code that may write shared state
	reads bool // reads state a call may write: fields, elements, derefs
}

// effectsOf inspects a lowered expression. Calls to the runtime's pure
// helpers (checked arithmetic, option constructors) and conversions are not
// calls: they neither write shared state nor depend on evaluation order.
func effectsOf(e ast.Expr) effects {
	var f effects
	ast.Inspect(e, func(n ast.Node) bool {
		switch n := n.(type) {
		case *ast.FuncLit:
			return false
		case *ast.CallExpr:
			if !pureCall(n) {
				f.calls = true
			}
		case *ast.SelectorExpr:
			if id, ok := n.X.(*ast.Ident); !ok || id.Name != "rt" {
				f.reads = true
			}
		case *ast.IndexExpr, *ast.StarExpr, *ast.IndexListExpr:
			f.reads = true
		}
		return true
	})
	return f
}

var pureNames = []string{"Int", "Some", "Ok", "Fail", "Format", "Float", "Bool"}

func pureCall(c *ast.CallExpr) bool {
	fun := c.Fun
	for {
		switch x := fun.(type) {
		case *ast.IndexExpr:
			fun = x.X
			continue
		case *ast.IndexListExpr:
			fun = x.X
			continue
		case *ast.ParenExpr:
			fun = x.X
			continue
		}
		break
	}
	switch fn := fun.(type) {
	case *ast.Ident:
		switch fn.Name {
		case "int64", "float64", "string", "bool", "len", "cap", "uint32":
			return true
		}
	case *ast.SelectorExpr:
		if id, ok := fn.X.(*ast.Ident); ok && id.Name == "rt" {
			for _, prefix := range pureNames {
				if strings.HasPrefix(fn.Sel.Name, prefix) {
					return true
				}
			}
		}
	}
	return false
}

// trivial reports whether e is a literal or constant expression no statement
// can change.
func trivial(e ast.Expr) bool {
	switch e := e.(type) {
	case *ast.BasicLit:
		return true
	case *ast.Ident:
		return e.Name == "true" || e.Name == "false" || e.Name == "nil"
	case *ast.CompositeLit:
		return len(e.Elts) == 0
	case *ast.CallExpr:
		if id, ok := e.Fun.(*ast.Ident); ok && len(e.Args) == 1 {
			switch id.Name {
			case "int64", "float64", "string", "bool":
				return trivial(e.Args[0])
			}
		}
	case *ast.UnaryExpr:
		return trivial(e.X)
	case *ast.ParenExpr:
		return trivial(e.X)
	}
	return false
}

// operands lowers sibling expressions that one Go expression evaluates
// together, preserving the source order of their effects. Go orders calls but
// not a variable read against a later call, and statements an operand needs
// run before the whole expression. An operand that would be reordered is
// first captured in a temporary, positioned before the operand that forces it.
func (g *gen) operands(items []*syntax.Expression) []ast.Expr {
	types := make([]*checker.Type, len(items))
	for i, item := range items {
		types[i] = g.info(item).Type
	}
	return g.operandsAs(items, types)
}

// operandsAs is operands with the type each operand is used as.
func (g *gen) operandsAs(items []*syntax.Expression, types []*checker.Type) []ast.Expr {
	out := make([]ast.Expr, len(items))
	for i, item := range items {
		mark := len(g.fn.pre)
		out[i] = g.valueAs(item, types[i])
		after := effectsOf(out[i])
		grew := len(g.fn.pre) > mark
		var spills []ast.Stmt
		for j := 0; j < i; j++ {
			if trivial(out[j]) {
				continue
			}
			before := effectsOf(out[j])
			if id, ok := out[j].(*ast.Ident); ok {
				// A temporary or immutable variable cannot change; a mutable
				// one can be reassigned by the statements operand i needs.
				if !grew || !g.fn.mutables[id.Name] {
					continue
				}
			} else if !grew && !(before.calls && after.reads) && !(before.reads && after.calls) {
				continue
			}
			name := g.temp()
			spills = append(spills, define(name, out[j]))
			out[j] = ident(name)
		}
		if len(spills) > 0 {
			pre := append([]ast.Stmt{}, g.fn.pre[:mark]...)
			pre = append(pre, spills...)
			g.fn.pre = append(pre, g.fn.pre[mark:]...)
		}
	}
	return out
}

// spill captures e in a temporary so later siblings cannot observe it changing.
func (g *gen) spill(e ast.Expr) ast.Expr {
	if trivial(e) {
		return e
	}
	if _, ok := e.(*ast.Ident); ok {
		return e
	}
	name := g.temp()
	g.fn.pre = append(g.fn.pre, define(name, e))
	return ident(name)
}

var _ = token.ADD
