package compiler

import (
	"sort"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) arguments(args []syntax.Argument) string {
	var values []string
	for _, a := range args {
		value := g.expression(a.Value)
		if target := g.program.Expressions[a.Value].OptionalArgument; target != nil {
			value = "rt.NewAlternative(" + g.key(target) + ",\"some\",[]string{\"value\"},[]rt.Argument{{Name:\"value\",Value:" + value + "}})"
		}
		values = append(values, "{Name:"+quote(a.Name)+",Value:"+value+"}")
	}
	return "[]rt.Argument{" + strings.Join(values, ",") + "}"
}
func (g *generator) expression(e *syntax.Expression) string {
	if value, ok := g.booleans[e]; ok {
		return strconv.FormatBool(value)
	}
	info := g.program.Expressions[e]
	if info.ErrorSource == nil {
		return g.expressionValue(e, info)
	}
	original := *info
	original.Type = info.ErrorSource
	value := g.expressionValue(e, &original)
	cause := info.ErrorSource
	if cause.ID == "@std/Result" {
		cause = cause.Args[1]
		scope := ""
		if info.ScopedError {
			scope = "," + g.typeScope(cause)
		}
		return "rt.ErrorResult(" + value + "," + g.key(info.Type) + scope + ")"
	}
	if info.ScopedError {
		return "rt.ViewOf(\"@std/Error\"," + value + "," + g.typeScope(cause) + ")"
	}
	return value
}

func (g *generator) expressionValue(e *syntax.Expression, info *checker.Info) string {
	if info.Native == "index" {
		return g.locatedOperation(e, "rt.Index", g.expression(e.Left), g.expression(e.Right))
	}
	switch e.Kind {
	case syntax.KindIndex:
		return g.locatedOperation(e, "rt.Index", g.expression(e.Left), g.expression(e.Right))
	case syntax.KindMatch:
		g.expressionDepth++
		body := g.match(e.Left, e.Arms, func(a *syntax.Arm) string {
			body := g.body(a.Body)
			value := "rt.Unit{}"
			if a.Value != nil {
				value = g.expression(a.Value)
			}
			return body + "return " + value + "\n"
		})
		g.expressionDepth--
		return "func() rt.Value {\n" + body + "return rt.Panic(\"runtime invariant: exhaustive match\")\n}()"

	case syntax.KindNumber:
		if strings.HasSuffix(e.Text, "d") {
			return "rt.DecimalLiteral(" + quote(e.Text) + ")"
		}
		if strings.ContainsAny(e.Text, ".eE") {
			return "rt.Float(" + quote(e.Text) + ")"
		}
		return "rt.Integer(" + quote(e.Text) + ")"
	case syntax.KindBool:
		return e.Text
	case syntax.KindUnit:
		return "rt.Unit{}"
	case syntax.KindText:
		var values []string
		for _, p := range e.Parts {
			if p.Value != nil {
				values = append(values, "rt.Format("+g.expression(p.Value)+")")
			} else {
				values = append(values, quote(p.Text))
			}
		}
		return "rt.Text(" + strings.Join(values, ",") + ")"
	case syntax.KindName, syntax.KindApply:
		if info.Method != nil && info.Method.Contract == nil && info.Method.Native != "" && info.Method.Native != "contract" {
			member := e.Left
			return "rt.NativeMemberResult(" + g.expression(member.Left) + "," + quote(member.Text) + "," + g.key(info.Type.Result) + ")"
		}
		if info.Binding != nil {
			return g.binding(info.Binding)
		}
		if info.Symbol != nil {
			symbol := info.Symbol
			if symbol.Native != "" {
				return "rt.StandardFunction(" + quote(symbol.Native) + "," + g.key(info.Type.Result) + ")"
			}
			if len(symbol.Variables) > 0 {
				return g.specialize(symbol, info.TypeArgs)
			}
			return symbol.ID
		}
		if info.Constructor != nil {
			return "rt.NewAlternative(" + g.key(info.Constructor) + "," + quote(info.Case) + ",nil,nil)"
		}
	case syntax.KindMember:
		if info.Constructor != nil {
			return "rt.NewAlternative(" + g.key(info.Constructor) + "," + quote(info.Case) + ",nil,nil)"
		}
		if info.Method != nil && info.Method.Contract == nil && info.Method.Native != "" && info.Method.Native != "contract" {
			return "rt.NativeMemberResult(" + g.expression(e.Left) + "," + quote(e.Text) + "," + g.key(info.Type.Result) + "," + g.typeScope(g.program.Expressions[e.Left].Type) + ")"
		}
		if info.Method != nil {
			return "rt.Bind(" + g.expression(e.Left) + "," + g.key(info.Method.Contract) + "," + quote(e.Text) + "," + g.typeScope(g.program.Expressions[e.Left].Type) + ")"
		}
		if info.Native != "" {
			return "rt.NativeMember(" + g.expression(e.Left) + "," + quote(e.Text) + ")"
		}
		return "rt.Field(" + g.expression(e.Left) + "," + quote(e.Text) + ")"
	case syntax.KindCall:
		arguments := e.Args
		if info.Arguments != nil {
			arguments = info.Arguments
		}
		args := g.arguments(arguments)
		if info.Constructor != nil {
			if info.Native == "view" {
				return "rt.ViewOf(" + g.key(info.Type) + "," + g.expression(e.Args[0].Value) + "," + g.typeScope(g.program.Expressions[e.Args[0].Value].Type) + ")"
			}
			if info.Case != "" {
				labels := []string{}
				for _, cs := range checker.Cases(info.Constructor) {
					if cs.Name == info.Case {
						for _, f := range cs.Fields {
							labels = append(labels, f.Name)
						}
					}
				}
				return "rt.NewAlternative(" + g.key(info.Type) + "," + quote(info.Case) + "," + stringsGo(labels) + "," + args + ")"
			}
			if symbol := info.Constructor.Def.Symbol; symbol.Native == "" && recordDefaults(symbol.Decl) {
				callable := symbol.ID
				if len(symbol.Variables) > 0 {
					callable = g.specialize(symbol, info.Constructor.Args)
				}
				return g.locatedOperation(e, "rt.Invoke", "ctx", callable, args)
			}
			return g.locatedOperation(e, "rt.ConstructWithContext", "ctx", g.key(info.Type), args)
		}
		var callable string
		if info.Symbol != nil {
			if info.Symbol.Native != "" {
				callable = "rt.StandardFunction(" + quote(info.Symbol.Native) + "," + g.key(info.Type) + ")"
			} else {
				callable = info.Symbol.ID
				if len(info.Symbol.Variables) > 0 {
					callable = g.specialize(info.Symbol, info.TypeArgs)
				}
			}
		} else {
			callable = g.expression(e.Left)
		}
		return g.locatedOperation(e, "rt.Invoke", "ctx", callable, args)
	case syntax.KindList:
		var elements []string
		for _, item := range e.Elements {
			elements = append(elements, g.expression(item))
		}
		return "&rt.List{Type:" + g.key(info.Type) + ",Items:[]rt.Value{" + strings.Join(elements, ",") + "}}"
	case syntax.KindMap:
		var entries []string
		for at := 0; at < len(e.Elements); at += 2 {
			entries = append(entries, "{Key:"+g.expression(e.Elements[at])+",Value:"+g.expression(e.Elements[at+1])+"}")
		}
		return g.locatedOperation(e, "rt.MapLiteral", "ctx", g.key(info.Type), "[]rt.Entry{"+strings.Join(entries, ",")+"}", g.typeScope(info.Type))
	case syntax.KindUnary:
		if e.Text == "try" {
			scope := ""
			if info.ScopedPropagation {
				scope = "," + g.typeScope(info.PropagatedError)
			}
			return "rt.Try(" + g.expression(e.Right) + scope + ")"
		}
		if e.Text == "-" && e.Right.Kind == syntax.KindNumber && e.Right.Text == "9223372036854775808" {
			return "rt.Integer(\"-9223372036854775808\")"
		}
		return g.locatedOperation(e, "rt.Unary", quote(e.Text), g.expression(e.Right))
	case syntax.KindBinary:
		if e.Text == "and" || e.Text == "or" {
			op := "&&"
			if e.Text == "or" {
				op = "||"
			}
			return "(rt.Bool(" + g.expression(e.Left) + ")" + op + "rt.Bool(" + g.expression(e.Right) + "))"
		}
		if e.Text == "==" || e.Text == "!=" {
			return g.locatedOperation(e, "rt.Equality", "ctx", quote(e.Text), g.expression(e.Left), g.expression(e.Right), g.typeScope(g.program.Expressions[e.Left].Type))
		}
		return g.locatedOperation(e, "rt.Binary", quote(e.Text), g.expression(e.Left), g.expression(e.Right))
	case syntax.KindLambda:
		captures := append([]*checker.Binding{}, info.Captures...)
		sort.Slice(captures, func(i, j int) bool { return captures[i].ID < captures[j].ID })
		var declarations, values []string
		old := map[*checker.Binding]string{}
		for _, b := range captures {
			values = append(values, g.binding(b))
			old[b] = g.captures[b]
			snapshot := g.temp()
			g.captures[b] = snapshot
			declarations = append(declarations, snapshot+" rt.Value")
		}
		result := e.Result
		if result == nil {
			result = &syntax.Type{Pos: e.Pos}
		}
		fn := g.function("<anonymous>", e.Params, result, e.Body, g.program.LambdaParameters[e], nil, info.Type)
		for _, b := range captures {
			if old[b] == "" {
				delete(g.captures, b)
			} else {
				g.captures[b] = old[b]
			}
		}
		return "func(" + strings.Join(declarations, ",") + ") rt.Function{return " + fn + "}(" + strings.Join(values, ",") + ")"
	}
	panic("missing lowering for " + e.Kind)
}

// locatedOperation updates the active frame only after evaluating its operands.
// Nested calls can therefore report their own sites without hiding this call site
// when they succeed. SourceAt inlines to an assignment; no expression closures or
// per-operation recovery are needed.
func (g *generator) locatedOperation(e *syntax.Expression, operation string, args ...string) string {
	last := len(args) - 1
	args[last] = "rt.SourceAt(&sourcePosition," + quote(e.Pos.String()) + "," + args[last] + ")"
	return operation + "(" + strings.Join(args, ",") + ")"
}
