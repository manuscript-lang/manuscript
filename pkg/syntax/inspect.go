package syntax

// Nodes visits every node of a module, including written types, patterns, and
// match arms, which Visitor leaves out. Each callback is optional. A node is
// visited before its children.
type Nodes struct {
	Declaration func(*Declaration)
	Statement   func(*Statement)
	Expression  func(*Expression)
	Pattern     func(*Pattern)
	Arm         func(*Arm)
	Type        func(*Type)
}

// Module visits every node of m.
func (n Nodes) Module(m *Module) {
	for _, d := range m.Declarations {
		n.declaration(d)
	}
}

func (n Nodes) declaration(d *Declaration) {
	if d == nil {
		return
	}
	if n.Declaration != nil {
		n.Declaration(d)
	}
	for _, p := range d.TypeParams {
		for _, b := range p.Bounds {
			n.typ(b)
		}
	}
	n.parameters(d.Fields)
	for _, c := range d.Cases {
		n.parameters(c.Fields)
	}
	n.parameters(d.Params)
	n.typ(d.Result)
	n.typ(d.Contract)
	n.typ(d.Receiver)
	n.statements(d.Body)
	for _, m := range d.Methods {
		n.declaration(m)
	}
}

func (n Nodes) parameters(params []Parameter) {
	for _, p := range params {
		n.typ(p.Type)
		n.expression(p.Default)
	}
}

func (n Nodes) typ(t *Type) {
	if t == nil {
		return
	}
	if n.Type != nil {
		n.Type(t)
	}
	for _, a := range t.Args {
		n.typ(a)
	}
	n.parameters(t.Params)
	n.typ(t.Result)
}

func (n Nodes) statements(body []*Statement) {
	for _, s := range body {
		if n.Statement != nil {
			n.Statement(s)
		}
		n.pattern(s.Pattern)
		n.typ(s.Type)
		n.expression(s.Target)
		n.expression(s.Value)
		n.statements(s.Body)
		n.statements(s.Else)
	}
}

func (n Nodes) pattern(p *Pattern) {
	if p == nil {
		return
	}
	if n.Pattern != nil {
		n.Pattern(p)
	}
	for _, e := range p.Elements {
		n.pattern(e)
	}
	for _, f := range p.Fields {
		n.pattern(f.Pattern)
	}
}

func (n Nodes) expression(e *Expression) {
	if e == nil {
		return
	}
	if n.Expression != nil {
		n.Expression(e)
	}
	n.expression(e.Left)
	n.expression(e.Right)
	for _, a := range e.Args {
		n.expression(a.Value)
	}
	for _, t := range e.Types {
		n.typ(t)
	}
	for _, item := range e.Elements {
		n.expression(item)
	}
	for _, part := range e.Parts {
		n.expression(part.Value)
	}
	n.parameters(e.Params)
	n.typ(e.Result)
	n.statements(e.Body)
	for i := range e.Arms {
		arm := &e.Arms[i]
		if n.Arm != nil {
			n.Arm(arm)
		}
		n.expression(arm.Path)
		n.statements(arm.Body)
		n.expression(arm.Value)
	}
}
