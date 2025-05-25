package ast

// Function Declarations

type FnDecl struct {
	NamedNode
	Parameters []Parameter
	ReturnType TypeAnnotation
	CanThrow   bool // true if function has ! modifier
	Body       *CodeBlock
}

type Parameter struct {
	NamedNode
	Type         TypeAnnotation
	DefaultValue Expression
}

// Method Declarations
type MethodsDecl struct {
	BaseNode
	TypeName  string // The type these methods are for
	Interface string // The interface being implemented
	Methods   []MethodImpl
}

type MethodImpl struct {
	NamedNode
	Parameters []Parameter
	ReturnType TypeAnnotation
	CanThrow   bool // true if method has ! modifier
	Body       *CodeBlock
}

// Function Expression
type FnExpr struct {
	TypedNode
	Parameters []Parameter
	ReturnType TypeAnnotation
	Body       *CodeBlock
}
