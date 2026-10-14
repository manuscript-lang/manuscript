package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
)

func primitiveListSuffix(t *checker.Type) string {
	if t == nil || t.ID != "@std/List" || len(t.Args) != 1 {
		return ""
	}
	switch primitiveEqualityType(t.Args[0]) {
	case "int64":
		return "Int"
	case "float64":
		return "Float"
	case "bool":
		return "Bool"
	case "string":
		return "String"
	}
	return ""
}
func (g *generator) typedListAtSuffix(e *syntax.Expression) string {
	if e == nil || e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return ""
	}
	info := g.program.Info(e.Left)
	if info == nil || info.Method == nil || info.Method.Contract != nil || info.Method.Native != "collections/at" {
		return ""
	}
	args := e.Args
	if converted := g.program.Info(e).Arguments; converted != nil {
		args = converted
	}
	if len(args) != 1 {
		return ""
	}
	return primitiveListSuffix(g.program.Info(e.Left.Left).Type)
}
func (g *generator) typedListAt(e *syntax.Expression) ast.Expr {
	suffix := g.typedListAtSuffix(e)
	if suffix == "" {
		return nil
	}
	args := e.Args
	if converted := g.program.Info(e).Arguments; converted != nil {
		args = converted
	}
	receiver := sourceAt(e.Left.Left.Pos, g.expression(e.Left.Left))
	return g.locatedOperation(e, runtimeName("ListAt"+suffix), ident("ctx"), receiver, g.scalarValue(args[0].Value))
}
func (g *generator) typedUnwrapAt(e *syntax.Expression) bool {
	if e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return false
	}
	info := g.program.Info(e.Left)
	if info == nil || info.Method == nil || info.Method.Contract != nil || info.Method.Native != "optional/unwrap" {
		return false
	}
	args := e.Args
	if converted := g.program.Info(e).Arguments; converted != nil {
		args = converted
	}
	return len(args) == 0 && g.typedListAtSuffix(e.Left.Left) != ""
}
func (g *generator) typedCollectionScalar(e *syntax.Expression) bool {
	if g.typedUnwrapAt(e) {
		return true
	}
	if e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return false
	}
	info := g.program.Info(e.Left)
	if info == nil || info.Method == nil || info.Method.Contract != nil || info.Method.Native != "length" {
		return false
	}
	t := g.program.Info(e.Left.Left).Type
	return len(e.Args) == 0 && (t.ID == "@std/List" || t.ID == "@std/Map" || t.ID == "@std/Set")
}
