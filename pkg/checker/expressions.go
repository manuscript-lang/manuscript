package checker

import (
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/internal/decimal"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (c *checker) expression(e *syntax.Expression, expected *Type) *Info {
	return c.checkExpression(e, c.infer(e, expected), expected)
}

func (c *checker) checkExpression(e *syntax.Expression, i *Info, expected *Type) *Info {
	if i.Type == nil {
		i.Type = primitive("<invalid>")
	}
	if i.Type.ID == "Never" {
		i.NoReturn = true
	}
	if expected != nil && i.Type.ID != "<invalid>" && !compatible(i.Type, expected) {
		if c.errorAssignable(i.Type, expected) {
			i.ErrorSource = i.Type
			cause := i.Type
			if std(cause, "Result") && len(cause.Args) == 2 {
				cause = cause.Args[1]
			}
			i.ScopedError = c.errorNeedsScope(cause)
			i.Type = expected
		} else {
			c.error(e.Pos, "type", c.assignmentMismatch(i.Type, expected))
		}
	}
	if expected != nil && expected.Kind == "function" && Same(i.Type, expected) {
		i.Type = expected
	}
	if e != nil && e.Kind != syntax.KindLambda {
		child := func(value *syntax.Expression) {
			if info := c.Expressions[value]; info != nil {
				i.Breaks = i.Breaks || info.Breaks
			}
		}
		child(e.Left)
		child(e.Right)
		for _, arg := range e.Args {
			child(arg.Value)
		}
		for _, element := range e.Elements {
			child(element)
		}
		for _, part := range e.Parts {
			child(part.Value)
		}
	}
	c.Expressions[e] = i
	return i
}
func (c *checker) infer(e *syntax.Expression, expected *Type) *Info {
	c.captureScope(e)
	i := &Info{}
	if e == nil {
		i.Type = primitive("Unit")
		return i
	}
	switch e.Kind {
	case syntax.KindNumber:
		return c.inferNumber(e, expected, i)
	case syntax.KindBool:
		i.Type = primitive("Bool")
	case syntax.KindUnit:
		i.Type = primitive("Unit")
	case syntax.KindText:
		return c.inferText(e, expected, i)
	case syntax.KindName:
		return c.inferName(e, expected, i)
	case syntax.KindIndex:
		return c.index(e)
	case syntax.KindMatch:
		return c.matchExpression(e, expected, false)
	case syntax.KindApply:
		return c.inferApply(e, expected, i)
	case syntax.KindMember:
		return c.inferMember(e, expected, i)
	case syntax.KindCall:
		return c.call(e, expected)
	case syntax.KindLambda:
		return c.callback(e, expected)
	case syntax.KindList:
		return c.inferList(e, expected, i)
	case syntax.KindMap:
		return c.inferMapLiteral(e, expected, i)
	case syntax.KindUnary:
		return c.inferUnary(e, expected, i)
	case syntax.KindBinary:
		return c.inferBinary(e, expected, i)
	default:
		c.error(e.Pos, "type", "unsupported expression "+e.Kind+"; rewrite it with supported syntax (see documentation/core-language)")
	}
	return finishInfo(i)
}

// finishInfo marks an expression of type Never as not returning.
func finishInfo(i *Info) *Info {
	if i.Type != nil && i.Type.ID == "Never" {
		i.NoReturn = true
	}
	return i
}

func (c *checker) inferNumber(e *syntax.Expression, expected *Type, i *Info) *Info {
	name := "Int"
	if strings.HasSuffix(e.Text, "d") {
		name = "Decimal"
		if s := c.names[name]; s == nil || s != standardSymbols[name] {
			c.error(e.Pos, "resolution", "Decimal literal requires the canonical Decimal import; add: import Decimal from \"@std/decimal.ms\"")
		}
		i.Type = standard("Decimal")
		if !decimal.Valid(e.Text) {
			c.error(e.Pos, "type", "Decimal literal is outside the exact 34-digit representable grid; shorten it to 34 significant digits")
		}
	} else if strings.ContainsAny(e.Text, ".eE") {
		name = "Float"
		n, err := strconv.ParseFloat(e.Text, 64)
		if err != nil || math.IsInf(n, 0) {
			c.error(e.Pos, "type", "Float literal is outside finite binary64 range; use a smaller magnitude (about 1.8e308 at most)")
		}
		i.Type = primitive(name)
	} else {
		if _, err := strconv.ParseInt(e.Text, 10, 64); err != nil {
			c.error(e.Pos, "type", "Int literal is outside signed 64-bit range; use a value between -9223372036854775808 and 9223372036854775807, or BigInt")
		}
		i.Type = primitive(name)
	}
	return finishInfo(i)
}

func (c *checker) inferText(e *syntax.Expression, expected *Type, i *Info) *Info {
	i.Type = primitive("String")
	for _, part := range e.Parts {
		if part.Value != nil {
			p := c.expression(part.Value, nil)
			i.NoReturn = i.NoReturn || p.NoReturn
		}
	}
	return finishInfo(i)
}

func (c *checker) inferName(e *syntax.Expression, expected *Type, i *Info) *Info {
	if b := c.scope.binding(e.Text); b != nil {
		i.Type = b.Type
		i.Binding = b
		if b.Function != c.function {
			if c.captures[c.function] != nil {
				c.captures[c.function][b] = true
			}
		}
		return i
	}
	if s := c.names[e.Text]; s != nil {
		if s.Kind == syntax.KindType {
			c.error(e.Pos, "type", "type name requires a constructor call; write "+e.Text+"(field: value, ...) to build a value")
			i.Type = primitive("<invalid>")
		} else {
			i.Type = s.Type
			i.Symbol = s
			if len(s.Variables) > 0 {
				c.error(e.Pos, "type", "a generic function value requires explicit specialization; write "+e.Text+"[Type] or call it with arguments")
			}
		}
		return i
	}
	typ, cs := c.findCase(e.Text, e.Pos)
	if typ != nil && len(cs.Fields) == 0 {
		i.Constructor = c.instantiate(typ, nil, nil, expected, e.Pos)
		i.Case = cs.Name
		i.Type = i.Constructor
	} else {
		c.error(e.Pos, "resolution", c.unknownName(e.Text))
	}
	return finishInfo(i)
}

func (c *checker) inferApply(e *syntax.Expression, expected *Type, i *Info) *Info {
	if callable := c.nativeCallable(e); callable != nil {
		*i = *callable
		args := c.resolveArguments(e.Types)
		if callable.Type.ID == "<invalid>" {
			return i
		}
		i.Type = c.specialize(callable.Type, callable.Method.Variables, args, e.Pos, calleeName(e))
		c.Expressions[e.Left] = i
		return i
	}
	if s := c.functionSymbol(e.Left); s != nil {
		args := c.resolveArguments(e.Types)
		i.Symbol = s
		i.Type = c.specialize(s.Type, s.Variables, args, e.Pos, calleeName(e))
		i.TypeArgs = args
	} else {
		typ := c.typeExpression(e)
		if typ != nil {
			c.error(e.Pos, "type", "type application requires construction; add (field: value, ...) after the type arguments")
			i.Type = typ
		} else {
			if e.Right != nil {
				return c.index(e)
			}
			if e.Left.Kind == syntax.KindName && c.scope.binding(e.Left.Text) == nil && c.names[e.Left.Text] == nil {
				c.error(e.Left.Pos, "resolution", c.unknownName(e.Left.Text))
				i.Type = primitive("<invalid>")
				return i
			}
			c.error(e.Pos, "resolution", "brackets require type arguments on a generic declaration or one Int index on a List")
		}
	}
	return finishInfo(i)
}

func (c *checker) inferMember(e *syntax.Expression, expected *Type, i *Info) *Info {
	if typ := c.typeExpression(e.Left); typ != nil {
		if typ.Kind == "contract" {
			c.error(e.Pos, "resolution", c.interfaceTypeMember(typ))
			return i
		}
		cs, ok := caseOf(typ, e.Text)
		if ok && len(cs.Fields) == 0 {
			i.Constructor = c.instantiate(typ, nil, nil, expected, e.Pos)
			i.Type = i.Constructor
			i.Case = e.Text
			return i
		}
		c.error(e.Pos, "resolution", "unknown or non-nullary alternative case "+e.Text+" of "+typ.Name+"; cases: "+list(caseNames(typ), 12)+" (cases with payloads need call syntax)")
		i.Type = primitive("<invalid>")
		return i
	}
	receiver := c.expression(e.Left, nil)
	i.NoReturn = receiver.NoReturn
	if receiver.Type.ID == "<invalid>" {
		return i
	}
	for _, f := range Fields(receiver.Type) {
		if receiver.Type.Kind == syntax.KindRecord && f.Name == e.Text && e.Text != "toString" {
			i.Type = f.Type
			return i
		}
	}
	if receiver.Type.ID == "Int" && (e.Text == "seconds" || e.Text == "milliseconds" || e.Text == "minutes") {
		i.Type = standard("Duration")
		i.Native = e.Text
		return i
	}
	methods := c.methods(receiver.Type, e.Text)
	if len(methods) != 1 {
		c.error(e.Pos, "resolution", c.unknownMember(receiver.Type, e.Text))
		return i
	}
	i.Method = methods[0]
	i.Type = methods[0].Type
	i.Native = methods[0].Native
	if methods[0].Native != "" && methods[0].Native != "contract" && len(methods[0].Variables) > 0 {
		c.error(e.Pos, "type", "a generic method value requires explicit specialization; write the type arguments or call it with arguments")
	}
	return finishInfo(i)
}

func (c *checker) inferList(e *syntax.Expression, expected *Type, i *Info) *Info {
	if s := c.names["List"]; s == nil || s != standardSymbols["List"] {
		c.error(e.Pos, "resolution", "list literal requires the canonical List type; rename the shadowing List declaration or binding")
	}
	var element *Type
	if std(expected, "List") && len(expected.Args) == 1 {
		element = expected.Args[0]
	}
	if element == nil {
		for _, item := range e.Elements {
			if !c.contextual(item) {
				v := c.expression(item, nil)
				if element == nil && v.Type.ID != "Never" {
					element = v.Type
				}
			}
		}
	}
	if element == nil {
		if !c.unknownType {
			c.error(e.Pos, "type", "cannot infer list element type; add an annotation, e.g. let xs: List[Int] = []")
		}
		element = primitive("<invalid>")
	}
	for _, item := range e.Elements {
		v := c.expression(item, element)
		i.NoReturn = i.NoReturn || v.NoReturn
	}
	i.Type = standard("List", element)
	return finishInfo(i)
}

func (c *checker) inferMapLiteral(e *syntax.Expression, expected *Type, i *Info) *Info {
	if s := c.names["Map"]; s == nil || s != standardSymbols["Map"] {
		c.error(e.Pos, "resolution", "map literal requires the canonical Map type; rename the shadowing Map declaration or binding")
	}
	var types [2]*Type
	if std(expected, "Map") && len(expected.Args) == 2 {
		copy(types[:], expected.Args)
	}
	for index := range types {
		if types[index] == nil {
			for at := index; at < len(e.Elements); at += 2 {
				item := e.Elements[at]
				if !c.contextual(item) {
					v := c.expression(item, nil)
					if types[index] == nil && v.Type.ID != "Never" {
						types[index] = v.Type
					}
				}
			}
		}
		if types[index] == nil {
			c.error(e.Pos, "type", "cannot infer map key or value type; add an annotation, e.g. let m: Map[String, Int] = {}")
			types[index] = primitive("<invalid>")
		}
	}
	for at, item := range e.Elements {
		v := c.expression(item, types[at%2])
		i.NoReturn = i.NoReturn || v.NoReturn
	}
	i.Type = standard("Map", types[0], types[1])
	c.wellFormed(i.Type, e.Pos, map[string]bool{})
	return finishInfo(i)
}

func (c *checker) inferUnary(e *syntax.Expression, expected *Type, i *Info) *Info {
	if e.Text == "-" && e.Right.Kind == syntax.KindNumber && e.Right.Text == "9223372036854775808" {
		i.Type = primitive("Int")
		c.Expressions[e.Right] = &Info{Type: i.Type}
		return i
	}
	v := c.expression(e.Right, nil)
	i.NoReturn = v.NoReturn
	switch e.Text {
	case "not":
		if !compatible(v.Type, primitive("Bool")) {
			c.error(e.Pos, "type", "not requires Bool, found "+v.Type.String()+"; compare explicitly, e.g. not (x == 0)")
		}
		i.Type = primitive("Bool")
	case "try":
		c.checkTry(e, v, i)
	default:
		if !numeric(v.Type) {
			c.error(e.Pos, "type", "numeric sign requires an independently known numeric operand, found "+v.Type.String()+"; apply + or - to Int, Float, or Decimal")
		}
		i.Type = v.Type
	}
	return finishInfo(i)
}

// checkTry types `try operand`: the operand must be a Result whose error the
// enclosing function can return, either unchanged or through an Error boundary.
func (c *checker) checkTry(e *syntax.Expression, operand, i *Info) {
	result := operand.Type
	if !std(result, "Result") || len(result.Args) != 2 {
		c.error(e.Pos, "type", "try requires Result, found "+result.String()+"; apply try only to a call returning Result[T, E]")
		return
	}
	if c.returnInference != nil {
		c.returnInference.contextDependent = true
	}
	i.Type = result.Args[0]
	if !std(c.result, "Result") || len(c.result.Args) != 2 {
		if c.testFunction != 0 && c.function == c.testFunction {
			c.error(e.Pos, "type", "try is not available in a test, which cannot return Result; match the result and end the failing arm with 'return panic(message: ...)'")
		} else {
			c.error(e.Pos, "type", "try requires an enclosing Result; declare this function to return Result[T, E] or handle the error with match")
		}
		return
	}
	failure, returned := result.Args[1], c.result.Args[1]
	if Same(returned, failure) {
		return
	}
	if !c.errorAssignable(failure, returned) {
		c.error(e.Pos, "type", "try requires the same error type or an Error boundary implemented by the specific error; this function returns "+c.result.String()+" but the operand fails with "+failure.String()+", so change the return error type or implement Error for it")
		return
	}
	i.PropagatedError = failure
	i.ScopedPropagation = c.errorNeedsScope(failure)
}

func isOrdering(op string) bool { return op == "<" || op == "<=" || op == ">" || op == ">=" }

func (c *checker) inferBinary(e *syntax.Expression, expected *Type, i *Info) *Info {
	a := c.expression(e.Left, nil)
	b := c.expression(e.Right, nil)
	logical := e.Text == "and" || e.Text == "or"
	i.NoReturn = a.NoReturn || (!logical && b.NoReturn)
	switch {
	case logical:
		i.Type = primitive("Bool")
		if !compatible(a.Type, i.Type) || !compatible(b.Type, i.Type) {
			c.error(e.Pos, "type", "logical operands require Bool, found "+a.Type.String()+" and "+b.Type.String()+"; compare explicitly, e.g. x != 0")
		}
		return i
	case (e.Text == "+" || e.Text == "-") && isTimeOperand(a.Type, b.Type):
		c.checkTimeArithmetic(e, a.Type, b.Type, i)
		return i
	}
	common := a.Type
	if common.ID == "Never" {
		common = b.Type
	}
	if common.ID == "Never" || !compatible(a.Type, common) || !compatible(b.Type, common) {
		c.error(e.Pos, "type", fmt.Sprintf("operator operands require the same independently known type, found %s %s %s; convert one side so both have one type (e.g. toString() for text, or an Int/Float conversion)", a.Type, e.Text, b.Type))
		c.unknownType = true // later "<invalid>" diagnostics only restate this one
		i.Type = primitive("<invalid>")
		if e.Text == "==" || e.Text == "!=" || isOrdering(e.Text) {
			i.Type = primitive("Bool")
		}
		return i
	}
	switch {
	case e.Text == "==" || e.Text == "!=":
		i.Type = primitive("Bool")
		if !c.property(common, "Equal", nil) {
			c.error(e.Pos, "type", "equality requires Equal operands; "+common.String()+" has no equality, so add 'impl Equal for "+common.String()+":' or compare fields")
		}
	case isOrdering(e.Text):
		i.Type = primitive("Bool")
		if !numeric(common) && common.ID != "String" && !std(common, "Duration") && !std(common, "Instant") {
			c.error(e.Pos, "type", "ordering requires numeric, String, or time operands, found "+common.String()+"; compare a numeric field or convert first")
		}
	default:
		i.Type = common
		if !numeric(common) && !(common.ID == "String" && e.Text == "+") && !(std(common, "Duration") && (e.Text == "+" || e.Text == "-")) {
			c.error(e.Pos, "type", "arithmetic requires numeric operands")
		}
		if e.Text == "%" && common.ID != "Int" {
			c.error(e.Pos, "type", "remainder requires Int operands, found "+common.String()+"; convert to Int or use math functions")
		}
	}
	return finishInfo(i)
}

func isTimeOperand(types ...*Type) bool {
	for _, t := range types {
		if std(t, "Duration") || std(t, "Instant") {
			return true
		}
	}
	return false
}

// timeArithmetic lists the operand and result types of the allowed time operators.
var timeArithmetic = []struct{ op, left, right, result string }{
	{"+", "Duration", "Duration", "Duration"}, {"-", "Duration", "Duration", "Duration"},
	{"+", "Instant", "Duration", "Instant"}, {"-", "Instant", "Duration", "Instant"},
	{"-", "Instant", "Instant", "Duration"},
}

func (c *checker) checkTimeArithmetic(e *syntax.Expression, left, right *Type, i *Info) {
	matches := 0
	for _, row := range timeArithmetic {
		if row.op == e.Text && compatible(left, standard(row.left)) && compatible(right, standard(row.right)) {
			i.Type = standard(row.result)
			matches++
		}
	}
	if matches != 1 {
		c.error(e.Pos, "type", "known operands must select exactly one time arithmetic operation; allowed: Duration±Duration, Instant±Duration, Instant-Instant")
	}
}

func numeric(t *Type) bool {
	return t != nil && (t.ID == "Int" || t.ID == "Float" || std(t, "Decimal"))
}
