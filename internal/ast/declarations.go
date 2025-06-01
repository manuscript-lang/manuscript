package ast

// Let Declarations

type LetDecl struct {
	BaseNode
	Items []LetItem
}

// LetItem represents different forms of let declarations
type LetItem interface {
	Node
}

type LetSingle struct {
	BaseNode
	ID    TypedID
	Value Expression
	IsTry bool
}

type LetBlock struct {
	BaseNode
	Items []LetBlockItem
}

type LetBlockItem interface {
	Node
}

type LetBlockItemSingle struct {
	BaseNode
	ID    TypedID
	Value Expression
}

type LetDestructuredObj struct {
	BaseNode
	IDs   []TypedID
	Value Expression
}

type LetDestructuredArray struct {
	BaseNode
	IDs   []TypedID
	Value Expression
}

// TypedID represents an identifier with optional type annotation
type TypedID struct {
	NamedNode
	Type TypeAnnotation
}

// Type and Interface Declarations

type TypeDecl struct {
	NamedNode
	Body TypeBody
}

type TypeBody interface {
	Node
}

type TypeDefBody struct {
	BaseNode
	Extends []TypeAnnotation
	Fields  []FieldDecl
}

type TypeAlias struct {
	BaseNode
	Type    TypeAnnotation
	Extends []TypeAnnotation
}

type FieldDecl struct {
	NamedNode
	Optional bool // true if field has ? modifier
	Type     TypeAnnotation
}

type InterfaceDecl struct {
	NamedNode
	Extends []TypeAnnotation
	Methods []InterfaceMethod
}

type InterfaceMethod struct {
	NamedNode
	Parameters []Parameter
	ReturnType TypeAnnotation
	CanThrow   bool // true if method has ! modifier
}
