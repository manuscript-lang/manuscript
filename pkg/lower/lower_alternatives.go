package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A direct function whose result is a Result or Optional returns the runtime's
// typed Result[T]/Option[T] (T a Go scalar or Value) instead of an Alternative.
// The typed form is produced and consumed only by return, try and match on a
// typed call; every other consumer receives the boxed Alternative, so nothing
// dynamic ever observes a typed value.
type altShape struct {
	optional bool
	payload  string // Go scalar type of the success payload, "" for Value
	key      string // checker.TypeKey of the whole result type
}

// alternativeShape returns the typed shape of a Result or Optional result type, or nil.
func alternativeShape(t *checker.Type) *altShape {
	if t == nil {
		return nil
	}
	switch {
	case t.ID == "@std/Result" && len(t.Args) == 2:
	case t.ID == "@std/Optional" && len(t.Args) == 1:
	default:
		return nil
	}
	return &altShape{optional: t.ID == "@std/Optional", payload: primitiveEqualityType(t.Args[0]), key: checker.TypeKey(t)}
}

func (a *altShape) typeExpr() ast.Expr {
	name := "Result"
	if a.optional {
		name = "Option"
	}
	var payload ast.Expr = runtimeName("Value")
	if a.payload != "" {
		payload = ident(a.payload)
	}
	return index(runtimeName(name), payload)
}

// unbox converts a boxed Alternative to the typed form.
func (a *altShape) unbox(value ast.Expr) ast.Expr {
	name := "ResultOf"
	if a.optional {
		name = "OptionOf"
	}
	var payload ast.Expr = runtimeName("Value")
	if a.payload != "" {
		payload = ident(a.payload)
	}
	return call(index(runtimeName(name), payload), value)
}

// failed is the Go condition that selects the error or none branch of tmp.
func (a *altShape) failed(tmp string) ast.Expr {
	if a.optional {
		return &ast.UnaryExpr{Op: token.NOT, X: selector(ident(tmp), "Some")}
	}
	return selector(ident(tmp), "Failed")
}

// typedReturn lowers a returned value in a function whose result is typed.
// Constructor calls build the typed form directly; typed calls pass through;
// anything else is unboxed.
func (g *generator) typedReturn(e *syntax.Expression) ast.Expr {
	shape := g.resultShape
	info := g.program.Info(e)
	if info.ErrorSource == nil && !info.Folded && checker.TypeKey(info.Type) == shape.key {
		if value, direct := g.typedDirectCall(e); value != nil && direct.shape != nil && direct.shape.key == shape.key {
			return value
		}
		if value := g.alternativeLiteral(e, info, shape); value != nil {
			return value
		}
	}
	return shape.unbox(g.expression(e))
}

// alternativeLiteral builds the typed form for ok/error/some/none, or nil.
func (g *generator) alternativeLiteral(e *syntax.Expression, info *checker.Info, shape *altShape) ast.Expr {
	if info.Constructor == nil || info.Native == "view" || info.Case == "" || info.Type.ID != map[bool]string{false: "@std/Result", true: "@std/Optional"}[shape.optional] {
		return nil
	}
	typ := shape.typeExpr()
	if e.Kind != syntax.KindCall {
		if info.Case == "none" && shape.optional {
			return composite(typ)
		}
		return nil
	}
	args := info.Arguments
	labels := g.caseLabels(info)
	if len(args) != 1 || len(labels) != 1 || args[0].Name != labels[0] {
		return nil
	}
	arg := args[0]
	switch {
	case info.Case == "ok" && !shape.optional, info.Case == "some" && shape.optional:
		var value ast.Expr
		if shape.payload != "" {
			value = g.scalar(arg.Value, shape.payload)
		} else {
			value = g.argumentValue(arg)
		}
		fields := []ast.Expr{keyed("Val", sourceAt(arg.Pos, value))}
		if shape.optional {
			fields = append(fields, keyed("Some", ident("true")))
		}
		return composite(typ, fields...)
	case info.Case == "error" && !shape.optional:
		return composite(typ, keyed("Cause", sourceAt(arg.Pos, g.argumentValue(arg))), keyed("Failed", ident("true")))
	}
	return nil
}

// typedMatch lowers a match on a typed call: the arms switch on the typed
// value's tag and bind its payload without boxing or assertions.
func (g *generator) typedMatch(tmp string, value ast.Expr, shape *altShape, arms []syntax.Arm, body func(*syntax.Arm) []ast.Stmt) []ast.Stmt {
	out := []ast.Stmt{define(tmp, value)}
	var cases []ast.Stmt
	for at := range arms {
		a := &arms[at]
		clause := &ast.CaseClause{}
		if a.Path.Text != "_" {
			clause.List = []ast.Expr{textLiteral(a.Path.Text)}
		}
		for _, b := range g.program.ArmBindingsFor(a) {
			if b == nil {
				continue
			}
			var payload ast.Expr
			native := ""
			if a.Path.Text == "error" {
				payload = selector(ident(tmp), "Cause")
			} else {
				payload, native = selector(ident(tmp), "Val"), shape.payload
			}
			if typ := g.declareTyped(b); typ != "" {
				if native != typ {
					payload = unbox(payload, typ)
				}
				clause.Body = append(clause.Body, &ast.DeclStmt{Decl: variable(b.ID, ident(typ), payload)})
			} else {
				clause.Body = append(clause.Body, &ast.DeclStmt{Decl: variable(b.ID, runtimeName("Value"), payload)})
			}
			clause.Body = append(clause.Body, discard(ident(b.ID)))
		}
		clause.Body = append(clause.Body, body(a)...)
		cases = append(cases, clause)
	}
	return append(out, &ast.SwitchStmt{Tag: call(selector(ident(tmp), "Tag")), Body: block(cases...)})
}
