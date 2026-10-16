package lower

import (
	"go/ast"
	"go/token"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// expr lowers e to a Go expression of goType(info.Type). Statements the
// expression needs first (hoisted matches, try, spilled operands) are
// appended to g.fn.pre and run before the statement that holds the expression.
func (g *gen) expr(e *syntax.Expression) ast.Expr {
	info := g.info(e)
	if info == nil {
		g.fail("%s: expression has no checked type", e.Pos)
		return ident("nil")
	}
	if info.Folded {
		return ident(strconv.FormatBool(info.Constant))
	}
	value := g.exprValue(e, info)
	if info.ErrorSource != nil {
		return g.errorBoundary(value, info)
	}
	return value
}

// valueAs lowers e for a context that expects type want. An expression that
// never returns is evaluated for its effect and replaced by a zero value.
func (g *gen) valueAs(e *syntax.Expression, want *checker.Type) ast.Expr {
	info := g.info(e)
	value := g.expr(e)
	if want != nil && info != nil && info.Type != nil && info.Type.ID == "Never" && g.sub(want).ID != "Never" {
		g.fn.pre = append(g.fn.pre, evaluated(value))
		return g.zero(want)
	}
	value = g.wrapOptional(e, value)
	if want != nil && info != nil && info.Type != nil {
		// A variable keeps the type it was declared with, whatever type the
		// use site expects.
		actual := info.Type
		if e.Kind == syntax.KindName && info.Binding != nil && info.Binding.Type != nil {
			actual = info.Binding.Type
		}
		value = g.convertFunction(value, g.sub(actual), g.sub(want))
	}
	return value
}

// adaptNative gives a native function the Go type of its function type when
// that type has defaulted parameters: natives take plain values, so the
// closure fills omitted arguments from the declaration.
func (g *gen) adaptNative(value ast.Expr, decl *syntax.Declaration, module string, t *checker.Type) ast.Expr {
	if t.Kind != "function" || len(t.Defaults) == 0 || decl == nil {
		return value
	}
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	args := []ast.Expr{ident("ctx")}
	for i := range t.Params {
		name := "a" + itoa(i)
		params = append(params, field(name, g.paramType(t, i)))
		if defaulted(t, i) {
			args = append(args, g.nativeFill(ident(name), t.Params[i].Type, decl, i, module))
		} else {
			args = append(args, ident(name))
		}
	}
	return closure(params, g.goType(t.Result), returned(call(value, args...)))
}

// convertFunction adapts a function value to the Go type of the function type
// it is used as when their defaulted parameters differ: a function that
// accepts omitted arguments is passed where every argument is supplied.
func (g *gen) convertFunction(value ast.Expr, from, want *checker.Type) ast.Expr {
	if from.Kind != "function" || want.Kind != "function" || len(from.Params) != len(want.Params) {
		return value
	}
	same := true
	for i := range want.Params {
		if defaulted(from, i) != defaulted(want, i) {
			same = false
		}
	}
	if same {
		return value
	}
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	args := []ast.Expr{ident("ctx")}
	for i := range want.Params {
		name := "a" + itoa(i)
		params = append(params, field(name, g.paramType(want, i)))
		switch {
		case defaulted(from, i) && !defaulted(want, i):
			args = append(args, rtCall("Given", ident(name)))
		case !defaulted(from, i) && defaulted(want, i):
			args = append(args, selector(ident(name), "Val"))
		default:
			args = append(args, ident(name))
		}
	}
	target := g.spill(value)
	return closure(params, g.goType(want.Result), returned(call(target, args...)))
}

// wrapOptional wraps a supplied argument once as some(value) when the checker
// marked it for an Optional parameter.
func (g *gen) wrapOptional(e *syntax.Expression, value ast.Expr) ast.Expr {
	if info := g.info(e); info != nil && info.OptionalArgument != nil {
		return call(generic(rtName("Some")), value)
	}
	return value
}

func (g *gen) exprValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	if info.Native == "index" {
		return g.indexValue(e)
	}
	switch e.Kind {
	case syntax.KindIndex:
		return g.indexValue(e)
	case syntax.KindMatch:
		return g.matchValue(e, info)
	case syntax.KindNumber:
		return g.number(e, info)
	case syntax.KindBool:
		return ident(e.Text)
	case syntax.KindUnit:
		return g.unit()
	case syntax.KindText:
		return g.text(e)
	case syntax.KindApply:
		// An explicit type application of a member, such as xs.map[String],
		// carries the member's own facts.
		if e.Left != nil && e.Left.Kind == syntax.KindMember {
			return g.member(e.Left, g.info(e.Left))
		}
		return g.name(e, info)
	case syntax.KindName:
		return g.name(e, info)
	case syntax.KindMember:
		return g.member(e, info)
	case syntax.KindCall:
		return g.callExpr(e, info)
	case syntax.KindList:
		return g.list(e, info)
	case syntax.KindMap:
		return g.mapLiteral(e, info)
	case syntax.KindUnary:
		return g.unary(e, info)
	case syntax.KindBinary:
		return g.binaryExpr(e, info)
	case syntax.KindLambda:
		return g.lambda(e, info)
	}
	g.fail("%s: missing lowering for expression %s", e.Pos, e.Kind)
	return ident("nil")
}

func (g *gen) number(e *syntax.Expression, info *checker.Info) ast.Expr {
	if strings.HasSuffix(e.Text, "d") {
		return rtCall("DecimalLiteral", textLiteral(e.Text))
	}
	if strings.ContainsAny(e.Text, ".eE") {
		value, _ := strconv.ParseFloat(e.Text, 64)
		return call(ident("float64"), &ast.BasicLit{Kind: token.FLOAT, Value: strconv.FormatFloat(value, 'g', -1, 64)})
	}
	return call(ident("int64"), signedInteger(e.Text))
}

// constantNumber reports whether e is a typed numeric literal Go folds.
func constantNumber(e ast.Expr) bool {
	c, ok := e.(*ast.CallExpr)
	if !ok || len(c.Args) != 1 {
		return false
	}
	if id, ok := c.Fun.(*ast.Ident); !ok || id.Name != "float64" {
		return false
	}
	switch x := c.Args[0].(type) {
	case *ast.BasicLit:
		return true
	case *ast.UnaryExpr:
		_, lit := x.X.(*ast.BasicLit)
		return lit
	}
	return false
}

func signedInteger(value string) ast.Expr {
	if strings.HasPrefix(value, "-") {
		return &ast.UnaryExpr{Op: token.SUB, X: &ast.BasicLit{Kind: token.INT, Value: value[1:]}}
	}
	return &ast.BasicLit{Kind: token.INT, Value: value}
}

// name lowers a reference to a variable, function, constant, or nullary case.
func (g *gen) name(e *syntax.Expression, info *checker.Info) ast.Expr {
	switch {
	case info.Binding != nil:
		return ident(g.bindingName(info.Binding))
	case info.Constructor != nil:
		return g.caseValue(info.Constructor, info.Case, nil)
	case info.Symbol != nil:
		return g.symbolValue(info.Symbol, info.TypeArgs, info)
	}
	g.fail("%s: %s names nothing lowerable", e.Pos, e.Text)
	return ident("nil")
}

// symbolValue is a top-level symbol used as a value: a constant is evaluated,
// a function becomes a Go function value.
func (g *gen) symbolValue(s *checker.Symbol, typeArgs []*checker.Type, info *checker.Info) ast.Expr {
	if s.Decl != nil && s.Decl.Constant {
		f := g.function(s, typeArgs)
		return call(ident(f.name), ident("ctx"))
	}
	if s.Native != "" {
		return g.adaptNative(g.nativeFunctionValue(s, typeArgs, info), s.Decl, s.Module, g.sub(info.Type))
	}
	f := g.function(s, typeArgs)
	// The Go function has the signature it was declared with; the use site may
	// have a type with fewer defaults.
	return g.convertFunction(ident(f.name), g.sub(f.typ), g.sub(info.Type))
}

// caseValue builds a sum-type case or a standard Optional/Result constructor.
func (g *gen) caseValue(t *checker.Type, name string, fields []ast.Expr) ast.Expr {
	t = g.sub(t)
	switch {
	case isStd(t, "Optional"):
		if name == "none" {
			return composite(g.goType(t))
		}
		return call(generic(rtName("Some")), fields...)
	case isStd(t, "Result"):
		targs := []ast.Expr{g.goType(t.Args[0]), g.goType(t.Args[1])}
		if name == "ok" {
			return call(generic(rtName("Ok"), targs...), fields...)
		}
		return call(generic(rtName("Fail"), targs...), fields...)
	case isStdType(t):
		return call(g.goType(t), g.stdCase(t, name, fields))
	}
	d := g.declare(t)
	var elements []ast.Expr
	for i, f := range g.caseFields(t, name) {
		elements = append(elements, keyed(fieldName(f.Name), fields[i]))
	}
	// Converting to the sum type keeps inferred variable and payload types abstract.
	return call(ident(d.name), composite(ident(g.caseName(d, name)), elements...))
}

// stdCase builds a case of a runtime-declared sum type.
func (g *gen) stdCase(t *checker.Type, name string, fields []ast.Expr) ast.Expr {
	var args []ast.Expr
	for _, a := range t.Args {
		args = append(args, g.goType(a))
	}
	typeName := strings.TrimPrefix(t.ID, "@std/") + "_" + sanitize(name)
	var elements []ast.Expr
	for i, f := range g.caseFields(t, name) {
		elements = append(elements, keyed(fieldName(f.Name), fields[i]))
	}
	return composite(generic(rtName(typeName), args...), elements...)
}

func (g *gen) caseFields(t *checker.Type, name string) []checker.Param {
	for _, c := range checker.Cases(g.sub(t)) {
		if c.Name == name {
			return c.Fields
		}
	}
	g.fail("%s has no case %s", t, name)
	return nil
}

// member lowers a field read, bound method, or qualified case.
func (g *gen) member(e *syntax.Expression, info *checker.Info) ast.Expr {
	if info.Constructor != nil {
		return g.caseValue(info.Constructor, info.Case, nil)
	}
	if info.Method == nil && info.Native != "" && g.info(e.Left).Type.ID == "Int" {
		// An Int duration unit property such as 2.seconds.
		fn := "Int_" + strings.ToUpper(info.Native[:1]) + info.Native[1:]
		g.noteNative(fn)
		return call(rtName(fn), ident("ctx"), g.expr(e.Left))
	}
	if info.Method != nil {
		return g.boundMethod(e, info)
	}
	receiver := g.expr(e.Left)
	return selector(receiver, fieldName(e.Text))
}

func (g *gen) text(e *syntax.Expression) ast.Expr {
	var result ast.Expr
	join := func(part ast.Expr) {
		if result == nil {
			result = part
			return
		}
		result = binary(result, token.ADD, part)
	}
	var values []*syntax.Expression
	for _, p := range e.Parts {
		if p.Value != nil {
			values = append(values, p.Value)
		}
	}
	operands := g.operands(values)
	next := 0
	for _, p := range e.Parts {
		if p.Value == nil {
			join(textLiteral(p.Text))
			continue
		}
		join(g.format(g.info(p.Value).Type, operands[next]))
		next++
	}
	if result == nil {
		return textLiteral("")
	}
	return result
}

func (g *gen) indexValue(e *syntax.Expression) ast.Expr {
	t := g.info(e.Left).Type
	operands := g.operandsAs([]*syntax.Expression{e.Left, e.Right}, []*checker.Type{t, intType})
	return call(generic(rtName("List_At"), g.goType(t.Args[0])), ident("ctx"), operands[0], operands[1])
}

func (g *gen) list(e *syntax.Expression, info *checker.Info) ast.Expr {
	elem := info.Type.Args[0]
	types := make([]*checker.Type, len(e.Elements))
	for i := range types {
		types[i] = elem
	}
	values := g.operandsAs(e.Elements, types)
	listType := generic(rtName("List"), g.goType(elem))
	return address(composite(listType, keyed("Items", sliceLiteral(g.goType(elem), values...))))
}

func (g *gen) mapLiteral(e *syntax.Expression, info *checker.Info) ast.Expr {
	key, value := info.Type.Args[0], info.Type.Args[1]
	types := make([]*checker.Type, len(e.Elements))
	for i := range types {
		types[i] = key
		if i%2 == 1 {
			types[i] = value
		}
	}
	operands := g.operandsAs(e.Elements, types)
	entry := generic(rtName("Entry"), g.goType(key), g.goType(value))
	var entries []ast.Expr
	for i := 0; i < len(operands); i += 2 {
		entries = append(entries, composite(nil, operands[i], operands[i+1]))
	}
	return call(generic(rtName("MapOf"), g.goType(key), g.goType(value)), g.keysFor(key), sliceLiteral(entry, entries...))
}

// unary lowers try, negation, and not.
func (g *gen) unary(e *syntax.Expression, info *checker.Info) ast.Expr {
	switch e.Text {
	case "try":
		return g.try(e, info)
	case "not":
		return not(g.valueAs(e.Right, boolType))
	case "-":
		operand := g.info(e.Right).Type
		switch operand.ID {
		case "Int":
			if e.Right.Kind == syntax.KindNumber {
				return call(ident("int64"), signedInteger("-"+e.Right.Text))
			}
			return rtCall("IntNegate", g.valueAs(e.Right, operand))
		case "Float":
			x := g.valueAs(e.Right, operand)
			if constantNumber(x) {
				x = rtCall("Float", x) // -0.0 must stay negative zero, which a Go constant cannot be
			}
			return &ast.UnaryExpr{Op: token.SUB, X: paren(x)}
		}
		return rtCall(typeBase(operand)+"Negate", g.valueAs(e.Right, operand))
	}
	g.fail("%s: unary %s", e.Pos, e.Text)
	return ident("nil")
}

func typeBase(t *checker.Type) string { return strings.TrimPrefix(t.ID, "@std/") }

var comparisons = map[string]token.Token{"<": token.LSS, "<=": token.LEQ, ">": token.GTR, ">=": token.GEQ}
var arithmetic = map[string]string{"+": "Add", "-": "Subtract", "*": "Multiply", "/": "Divide", "%": "Remainder"}
var arithmeticOps = map[string]token.Token{"+": token.ADD, "-": token.SUB, "*": token.MUL, "/": token.QUO}
var orderingNames = map[string]string{"<": "Less", "<=": "LessEqual", ">": "Greater", ">=": "GreaterEqual"}

func (g *gen) binaryExpr(e *syntax.Expression, info *checker.Info) ast.Expr {
	if e.Text == "and" || e.Text == "or" {
		return g.logical(e)
	}
	leftType, rightType := g.info(e.Left).Type, g.info(e.Right).Type
	operands := g.operandsAs([]*syntax.Expression{e.Left, e.Right}, []*checker.Type{leftType, rightType})
	a, b := operands[0], operands[1]
	if e.Text == "==" || e.Text == "!=" {
		eq := g.equal(leftType, a, b, e)
		if e.Text == "!=" {
			return not(eq)
		}
		return eq
	}
	switch {
	case leftType.ID == "Int" && rightType.ID == "Int":
		if op, ok := comparisons[e.Text]; ok {
			return binary(a, op, b)
		}
		return rtCall("Int"+arithmetic[e.Text], a, b)
	case leftType.ID == "Float" && rightType.ID == "Float":
		if op, ok := comparisons[e.Text]; ok {
			return binary(a, op, b)
		}
		if op, ok := arithmeticOps[e.Text]; ok {
			// Go folds constant operands exactly and rejects x / 0 and overflow;
			// Manuscript Float follows IEEE, so a constant left operand is hidden
			// from the compiler. Explicit rounding keeps each source operation
			// separate on FMA targets.
			if constantNumber(a) && constantNumber(b) {
				a = rtCall("Float", a)
			}
			return call(ident("float64"), binary(a, op, b))
		}
	case leftType.ID == "String":
		if op, ok := comparisons[e.Text]; ok {
			return binary(a, op, b)
		}
		return binary(a, token.ADD, b)
	}
	switch {
	case leftType.ID == "@std/Duration" && rightType.ID == "@std/Duration":
		if op, ok := comparisons[e.Text]; ok {
			return binary(a, op, b)
		}
		return call(rtName(map[string]string{"+": "Duration_Plus", "-": "Duration_Minus"}[e.Text]), ident("ctx"), a, b)
	case leftType.ID == "@std/Instant" && rightType.ID == "@std/Instant":
		if op, ok := comparisons[e.Text]; ok {
			return binary(call(rtName("Instant_Compare"), ident("ctx"), a, b), op, intLiteral(0))
		}
		return call(rtName("Instant_Difference"), ident("ctx"), a, b)
	case leftType.ID == "@std/Instant" && rightType.ID == "@std/Duration":
		if e.Text == "-" {
			return call(rtName("Instant_Unshift"), ident("ctx"), a, b)
		}
		return call(rtName("Instant_Shift"), ident("ctx"), a, b)
	}
	name := typeBase(leftType)
	if name2 := typeBase(rightType); name2 != name {
		name += "_" + name2
	}
	if op, ok := orderingNames[e.Text]; ok {
		return rtCall(name+op, a, b)
	}
	return rtCall(name+arithmetic[e.Text], a, b)
}

// logical lowers and/or. A right operand that needs statements runs only when
// the left operand does not already decide the result.
func (g *gen) logical(e *syntax.Expression) ast.Expr {
	left := g.valueAs(e.Left, boolType)
	saved := g.fn.pre
	g.fn.pre = nil
	right := g.valueAs(e.Right, boolType)
	pre := g.fn.pre
	g.fn.pre = saved
	op := token.LAND
	if e.Text == "or" {
		op = token.LOR
	}
	if len(pre) == 0 {
		return binary(paren(left), op, paren(right))
	}
	t := g.temp()
	cond := ident(t)
	var guard ast.Expr = cond
	if e.Text == "or" {
		guard = not(cond)
	}
	body := append(pre, assign(ident(t), token.ASSIGN, right))
	g.fn.pre = append(g.fn.pre, define(t, left), &ast.IfStmt{Cond: guard, Body: block(body...)})
	return ident(t)
}

// lambda lowers an anonymous function. Captured variables are snapshotted when
// the closure is created, which Go's by-reference capture does not do for
// variables that are later reassigned.
func (g *gen) lambda(e *syntax.Expression, info *checker.Info) ast.Expr {
	saved := g.fn
	defer func() { g.fn = saved }()
	result := g.sub(info.Type.Result)
	g.fn = &funcState{decl: saved.decl, result: result}
	var snapshots []ast.Stmt
	restore := map[*checker.Binding]*string{}
	for _, b := range sortedBindings(info.Captures) {
		if !b.Mutable {
			continue
		}
		name := g.temp()
		old, had := g.captured[b]
		if g.captured == nil {
			g.captured = map[*checker.Binding]string{}
		}
		snapshots = append(snapshots, define(name, ident(g.bindingNameIn(b, saved))))
		oldName := old
		restore[b] = &oldName
		if !had {
			restore[b] = nil
		}
		g.captured[b] = name
	}
	params := []*ast.Field{field("ctx", pointerTo(rtName("Execution")))}
	var prologue []ast.Stmt
	for i, b := range g.program.LambdaBindings(e) {
		fld, fill := g.parameter(b, info.Type, i, e.Params)
		params = append(params, fld)
		prologue = append(prologue, fill...)
	}
	g.markUsed(e.Params, e.Body)
	body := append(prologue, g.body(e.Body, result)...)
	body = g.finishBody(body, result)
	body = g.cleanupPrologue(body)
	fn := g.named(e, closure(params, g.goType(result), body...))
	for b, old := range restore {
		if old == nil {
			delete(g.captured, b)
		} else {
			g.captured[b] = *old
		}
	}
	saved.pre = append(saved.pre, snapshots...)
	return fn
}

// bindingNameIn is the identifier b has in the enclosing function.
func (g *gen) bindingNameIn(b *checker.Binding, _ *funcState) string { return g.bindingName(b) }

// named registers a lambda's code in fault traces as <anonymous>. The site
// variable makes registration a single atomic load after the first call.
func (g *gen) named(e *syntax.Expression, fn ast.Expr) ast.Expr {
	key := "site:" + e.Pos.String()
	if f := g.fn.decl; f != nil {
		key += "@" + f.key
	}
	site := g.helperFunc(key, "site", func(name string) ast.Decl {
		return &ast.GenDecl{Tok: token.VAR, Specs: []ast.Spec{&ast.ValueSpec{Names: []*ast.Ident{ident(name)}, Type: rtName("Site")}}}
	})
	return call(rtName("Named"), address(site), textLiteral("<anonymous>"), fn)
}
