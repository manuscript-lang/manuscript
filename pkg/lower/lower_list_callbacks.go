package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A List operation that takes a function literal (map, filter, fold,
// for_each, count, some, every) on a statically typed receiver is emitted as
// a Go loop over the captured list that calls the literal as a typed Go
// function: no Function value, argument slice or boxed result per element.
// Everything else about the call is unchanged: the receiver is read first, the
// literal's captures are snapshotted when it is created, each element runs
// after a cancellation check, and iteration uses the list as it was captured.

type listCallback struct {
	name     string   // operation: map, filter, fold, ...
	labels   []string // declared parameter names, receiver excluded
	callback int      // index of the function argument
}

var listCallbacks = map[string]listCallback{
	"map":      {"map", []string{"transform"}, 0},
	"filter":   {"filter", []string{"predicate"}, 0},
	"for_each": {"for_each", []string{"operation"}, 0},
	"count":    {"count", []string{"predicate"}, 0},
	"some":     {"some", []string{"predicate"}, 0},
	"every":    {"every", []string{"predicate"}, 0},
	"fold":     {"fold", []string{"initial", "step"}, 1},
}

func (g *generator) listCallbackCall(e *syntax.Expression, arguments []syntax.Argument) ast.Expr {
	member := e.Left
	if member.Kind == syntax.KindApply {
		member = member.Left
	}
	if !g.directOn || member.Kind != syntax.KindMember {
		return nil
	}
	callee := g.program.Info(member)
	if callee == nil || callee.Method == nil || callee.Method.Contract != nil {
		return nil
	}
	native := callee.Method.Native
	if len(native) > len("collections/") && native[:len("collections/")] == "collections/" {
		native = native[len("collections/"):]
	}
	op, ok := listCallbacks[native]
	if !ok || len(arguments) != len(op.labels) {
		return nil
	}
	for i, argument := range arguments {
		if argument.Name != op.labels[i] {
			return nil
		}
	}
	receiverType := g.program.Info(member.Left).Type
	info := g.program.Info(e)
	if receiverType == nil || receiverType.ID != "@std/List" || len(receiverType.Args) != 1 || hasTypeVariable(receiverType) || info == nil || hasTypeVariable(info.Type) || info.ErrorSource != nil {
		return nil
	}
	lambda := arguments[op.callback].Value
	if lambda.Kind != syntax.KindLambda {
		return nil
	}
	lambdaInfo := g.program.Info(lambda)
	if lambdaInfo == nil || lambdaInfo.Type == nil || lambdaInfo.Type.Kind != "function" || hasTypeVariable(lambdaInfo.Type) || lambdaInfo.ErrorSource != nil {
		return nil
	}
	bindings := g.program.LambdaBindings(lambda)
	params := lambdaInfo.Type.Params
	if len(bindings) != len(lambda.Params) || len(params) != len(lambda.Params) || len(params) != map[bool]int{false: 1, true: 2}[native == "fold"] {
		return nil
	}
	direct := &directFunction{result: primitiveEqualityType(lambdaInfo.Type.Result), shape: alternativeShape(lambdaInfo.Type.Result)}
	if direct.shape != nil {
		return nil
	}
	for i, p := range lambda.Params {
		if p.Default != nil || lambdaInfo.Type.Defaults[params[i].Name] {
			return nil
		}
		direct.params = append(direct.params, scalarBinding(bindings[i]))
		direct.defaulted = append(direct.defaulted, false)
	}
	elem := primitiveEqualityType(receiverType.Args[0])

	// Evaluation order matches an ordinary call: receiver, initial value, literal.
	source, element := g.temp(), g.temp()
	body := []ast.Stmt{define(source, g.expression(member.Left))}
	var initial ast.Expr
	accType := ""
	if native == "fold" {
		accType = primitiveEqualityType(info.Type)
		if accType != "" {
			initial = g.scalar(arguments[0].Value, accType)
		} else {
			initial = g.argumentValue(arguments[0])
		}
	}
	accumulator := g.temp()
	if native == "fold" {
		var accGo ast.Expr = runtimeName("Value")
		if accType != "" {
			accGo = ident(accType)
		}
		body = append(body, &ast.DeclStmt{Decl: variable(accumulator, accGo, initial)})
	}
	lam := g.directLambda(lambda, lambdaInfo, direct, bindings)
	function := g.temp()
	body = append(body, define(function, lam.expr))

	// coerce adapts a Go value of type have ("" is Value) to want.
	coerce := func(value ast.Expr, have, want string) ast.Expr {
		if want != "" && have == "" {
			return unbox(value, want)
		}
		return value
	}
	elementArg := coerce(ident(element), elem, direct.params[len(direct.params)-1])
	invoke := func(arguments ...ast.Expr) ast.Expr {
		return call(ident(function), append([]ast.Expr{ident("ctx")}, arguments...)...)
	}
	checkCancelled := evaluated(runtimeCall("CheckCancelled", ident("ctx")))
	iterate := "Iterate"
	if elem != "" {
		iterate += primitiveKinds[elem]
	}
	loop := func(statements ...ast.Stmt) ast.Stmt {
		return &ast.RangeStmt{Key: ident("_"), Value: ident(element), Tok: token.DEFINE, X: runtimeCall(iterate, ident(source)), Body: block(append([]ast.Stmt{checkCancelled}, statements...)...)}
	}
	predicate := func() ast.Expr { return coerce(invoke(elementArg), direct.result, "bool") }
	output := g.temp()
	resultList := func(typ string, items string, key ast.Expr) ast.Expr {
		if typ != "" {
			return runtimeCall("Own"+primitiveKinds[typ]+"List", key, ident(items))
		}
		return runtimeCall("NewList", key, ident(items))
	}
	itemType := func(typ string) ast.Expr {
		if typ != "" {
			return sliceOf(ident(typ))
		}
		return sliceOf(runtimeName("Value"))
	}
	switch native {
	case "map":
		out := primitiveEqualityType(info.Type.Args[0])
		body = append(body,
			&ast.DeclStmt{Decl: variable(output, itemType(out), nil)},
			loop(assign(ident(output), token.ASSIGN, call(ident("append"), ident(output), coerce(invoke(elementArg), direct.result, out)))),
			returned(resultList(out, output, g.key(info.Type))))
	case "filter":
		body = append(body,
			&ast.DeclStmt{Decl: variable(output, itemType(elem), nil)},
			loop(&ast.IfStmt{Cond: predicate(), Body: block(assign(ident(output), token.ASSIGN, call(ident("append"), ident(output), ident(element))))}),
			returned(resultList(elem, output, g.key(info.Type))))
	case "for_each":
		body = append(body, loop(discard(invoke(elementArg))), returned(unit()))
	case "count":
		body = append(body,
			&ast.DeclStmt{Decl: variable(output, ident("int64"), nil)},
			loop(&ast.IfStmt{Cond: predicate(), Body: block(&ast.IncDecStmt{X: ident(output), Tok: token.INC})}),
			returned(ident(output)))
	case "some":
		body = append(body, loop(&ast.IfStmt{Cond: predicate(), Body: block(returned(ident("true")))}), returned(ident("false")))
	case "every":
		body = append(body, loop(&ast.IfStmt{Cond: &ast.UnaryExpr{Op: token.NOT, X: predicate()}, Body: block(returned(ident("false")))}), returned(ident("true")))
	case "fold":
		step := invoke(coerce(ident(accumulator), accType, direct.params[0]), elementArg)
		body = append(body,
			loop(assign(ident(accumulator), token.ASSIGN, coerce(step, direct.result, accType))),
			returned(ident(accumulator)))
	default:
		return nil
	}
	return call(closure(nil, runtimeName("Value"), body...))
}
