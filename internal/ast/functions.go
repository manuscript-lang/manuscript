package ast

// Function Declarations

type FnDecl struct {
	NamedNode
	Parameters []Parameter
	ReturnType TypeAnnotation
	CanThrow   bool // true if function has ! modifier
	Body       *CodeBlock
}

func (d *FnDecl) Accept(v Visitor) {
	if v = v.Visit(d); v != nil {
		acceptParameters(v, d.Parameters)
		acceptOptional(v, d.ReturnType)
		acceptOptional(v, d.Body)
	}
}

type Parameter struct {
	NamedNode
	Type         TypeAnnotation
	DefaultValue Expression
}

func (p *Parameter) Accept(v Visitor) {
	if v = v.Visit(p); v != nil {
		p.Type.Accept(v)
		acceptOptional(v, p.DefaultValue)
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
	ReturnType TypeAnnotation
	CanThrow   bool // true if method has ! modifier
	Body       *CodeBlock
}

func (m *MethodImpl) Accept(v Visitor) {
	if v = v.Visit(m); v != nil {
		acceptParameters(v, m.Parameters)
		acceptOptional(v, m.ReturnType)
		acceptOptional(v, m.Body)
	}
}

// Function Expression
type FnExpr struct {
	TypedNode
	Parameters []Parameter
	ReturnType TypeAnnotation
	Body       *CodeBlock
}

func (f *FnExpr) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		acceptParameters(v, f.Parameters)
		acceptOptional(v, f.ReturnType)
		acceptOptional(v, f.Body)
	}
}

func acceptParameters(v Visitor, params []Parameter) {
	for _, param := range params {
		param.Accept(v)
	}
}

func acceptOptional(v Visitor, node Node) {
	if node != nil {
		node.Accept(v)
	}
}
