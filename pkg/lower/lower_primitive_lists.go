package lower

import (
	"fmt"
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func primitiveList(t *checker.Type) (string, string) {
	if t == nil || t.ID != "@std/List" || len(t.Args) != 1 {
		return "", ""
	}
	typ := primitiveEqualityType(t.Args[0])
	name := map[string]string{"int64": "Int", "float64": "Float", "bool": "Bool", "string": "String"}[typ]
	return typ, name
}

// Eligibility probes never lower operands: lowering registers source markers.
func (g *generator) listUnwrapTarget(e *syntax.Expression) (string, string) {
	if e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return "", ""
	}
	info := g.program.Info(e.Left)
	if info == nil || info.Method == nil || info.Method.Contract != nil || info.Method.Native != "optional/unwrap" || len(g.program.Info(e).Arguments) != 0 {
		return "", ""
	}
	at := e.Left.Left
	if !g.listAtMatch(at) {
		return "", ""
	}
	return primitiveList(g.program.Info(at.Left.Left).Type)
}

func (g *generator) primitiveCollectionType(e *syntax.Expression) string {
	if e.Kind != syntax.KindCall {
		return ""
	}
	if typ, _ := g.listUnwrapTarget(e); typ != "" {
		return typ
	}
	if e.Left.Kind != syntax.KindMember {
		return ""
	}
	callee := g.program.Info(e.Left)
	if callee == nil {
		return ""
	}
	method := callee.Method
	if method != nil && method.Contract == nil && method.Native == "length" && len(g.program.Info(e).Arguments) == 0 {
		switch g.program.Info(e.Left.Left).Type.ID {
		case "@std/List", "@std/Map", "@std/Set":
			return "int64"
		}
	}
	return ""
}

func (g *generator) primitiveListUnwrap(e *syntax.Expression) ast.Expr {
	_, name := g.listUnwrapTarget(e)
	if name == "" {
		return nil
	}
	at := e.Left.Left
	args := g.program.Info(at).Arguments
	receiver := sourceAt(at.Left.Left.Pos, g.expression(at.Left.Left))
	index := g.scalar(args[0].Value, "int64")
	optional := g.locatedOperation(at, runtimeName("ListAt"+name), ident("ctx"), receiver, index)
	return call(selector(optional, "Unwrap"), sourceAt(e.Pos, ident("ctx")))
}

func (g *generator) primitiveListLiteral(e *syntax.Expression, info *checker.Info) ast.Expr {
	typ, name := primitiveList(info.Type)
	if typ == "" {
		return nil
	}
	if len(e.Elements) > debugListThreshold && !g.debugLiterals {
		data := make([]ast.Expr, len(e.Elements))
		eligible := true
		for i, item := range e.Elements {
			data[i] = g.debugLiteralScalar(item)
			if data[i] == nil {
				eligible = false
				break
			}
		}
		if eligible {
			dataName := fmt.Sprintf("scalarLiteralData%d", len(g.literalData)+1)
			array := &ast.ArrayType{Len: intLiteral(len(data)), Elt: ident(typ)}
			g.literalData = append(g.literalData, variable(dataName, nil, composite(array, data...)))
			return runtimeCall("New"+name+"List", g.key(info.Type), &ast.SliceExpr{X: ident(dataName)})
		}
	}
	values := make([]ast.Expr, len(e.Elements))
	laterEffects := make([]bool, len(e.Elements))
	effect := false
	for i := len(e.Elements) - 1; i >= 0; i-- {
		laterEffects[i] = effect
		effect = effect || !g.exprFree(e.Elements[i])
	}
	for i, item := range e.Elements {
		values[i] = g.scalar(item, typ)
		if laterEffects[i] {
			values[i] = sourceAt(item.Pos, values[i])
		}
	}
	return runtimeCall("New"+name+"List", g.key(info.Type), sliceLiteral(ident(typ), values...))
}

func (g *generator) primitiveListLoop(s *syntax.Statement, body []ast.Stmt) ast.Stmt {
	typ, name := primitiveList(g.program.Info(s.Value).Type)
	if typ == "" {
		return nil
	}
	b := g.program.LoopBinding(s)
	captured, index := g.temp(), g.temp()
	body = append([]ast.Stmt{discard(ident(b.ID)), evaluated(runtimeCall("PollIndex", ident("ctx"), ident(index)))}, body...)
	loop := &ast.RangeStmt{Key: ident(index), Value: ident(b.ID), Tok: token.DEFINE, X: call(selector(ident(captured), "Values")), Body: block(body...)}
	return block(define(captured, runtimeCall("CaptureList"+name, g.expression(s.Value))), loop)
}
