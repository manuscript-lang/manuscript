package ast

// Function Declarations

type FnDecl struct {
	NamedNode
	Parameters []Parameter
	ReturnType TypeAnnotation // Optional, nil if no return type
	CanThrow   bool           // true if function has ! modifier
	Body       *CodeBlock
}

func (d *FnDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		for _, param := range d.Parameters {
			param.Accept(v)
		}
		if d.ReturnType != nil {
			d.ReturnType.Accept(v)
		}
		if d.Body != nil {
			d.Body.Accept(v)
		}
	}
}

type Parameter struct {
	NamedNode
	Type         TypeAnnotation
	DefaultValue Expression // Optional, nil if no default value
}

func (p *Parameter) Accept(v Visitor) {
	if v = v.Visit(p); v != nil {
		p.Type.Accept(v)
		if p.DefaultValue != nil {
			p.DefaultValue.Accept(v)
		}
	}
}

// Method Declarations

type MethodsDecl struct {
	BaseNode
	TypeName  string // The type these methods are for
	Interface string // The interface being implemented
	Methods   []MethodImpl
}

func (d *MethodsDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		for _, method := range d.Methods {
			method.Accept(v)
		}
	}
}

type MethodImpl struct {
	NamedNode
	Parameters []Parameter
	ReturnType TypeAnnotation // Optional, nil if no return type
	CanThrow   bool           // true if method has ! modifier
	Body       *CodeBlock
}

func (m *MethodImpl) Accept(v Visitor) {
	if v = v.Visit(m); v != nil {
		for _, param := range m.Parameters {
			param.Accept(v)
		}
		if m.ReturnType != nil {
			m.ReturnType.Accept(v)
		}
		if m.Body != nil {
			m.Body.Accept(v)
		}
	}
}

// Function Expression

type FnExpr struct {
	TypedNode
	Parameters []Parameter
	ReturnType TypeAnnotation // Optional, nil if no return type
	Body       *CodeBlock
}

func (f *FnExpr) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		for _, param := range f.Parameters {
			param.Accept(v)
		}
		if f.ReturnType != nil {
			f.ReturnType.Accept(v)
		}
		if f.Body != nil {
			f.Body.Accept(v)
		}
	}
}
