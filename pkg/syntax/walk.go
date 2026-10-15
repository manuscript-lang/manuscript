package syntax

// Visitor walks executable syntax in source order. Callers select the nodes
// they need without reproducing recursion through defaults, interpolation,
// closures, branches, and match arms. Types and patterns are not executable.
type Visitor struct {
	Block      func([]*Statement)
	Statement  func(*Statement)
	Expression func(*Expression)
	// LeaveExpression runs after all executable children, including arm bodies.
	LeaveExpression func(*Expression)
}

// Walk visits a declaration and its methods and accessors.
func (v Visitor) Walk(d *Declaration) {
	if d == nil {
		return
	}
	v.Callable(d.Params, d.Body)
	v.Callable(d.Fields, nil)
	for _, method := range d.Methods {
		v.Walk(method)
	}
}

// Callable visits defaults and a body, allowing a caller to retain its owner.
func (v Visitor) Callable(params []Parameter, body []*Statement) {
	for _, param := range params {
		v.expression(param.Default)
	}
	v.statements(body)
}

func (v Visitor) statements(body []*Statement) {
	if len(body) == 0 {
		return
	}
	if v.Block != nil {
		v.Block(body)
	}
	for _, s := range body {
		if v.Statement != nil {
			v.Statement(s)
		}
		v.expression(s.Target)
		v.expression(s.Value)
		v.statements(s.Body)
		v.statements(s.Else)
	}
}

func (v Visitor) expression(e *Expression) {
	if e == nil {
		return
	}
	if v.Expression != nil {
		v.Expression(e)
	}
	v.expression(e.Left)
	v.expression(e.Right)
	for _, arg := range e.Args {
		v.expression(arg.Value)
	}
	for _, item := range e.Elements {
		v.expression(item)
	}
	for _, part := range e.Parts {
		v.expression(part.Value)
	}
	v.Callable(e.Params, e.Body)
	for _, arm := range e.Arms {
		v.statements(arm.Body)
		v.expression(arm.Value)
	}
	if v.LeaveExpression != nil {
		v.LeaveExpression(e)
	}
}
