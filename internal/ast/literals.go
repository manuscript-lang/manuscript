package ast

// String literals

type StringLiteral struct {
	TypedNode
	Parts []StringPart
	Kind  StringKind
}

type StringKind int

const (
	SingleQuoted StringKind = iota
	DoubleQuoted
	MultiQuoted
	MultiDoubleQuoted
)

type StringContent struct {
	BaseNode
	Content string
}

type StringInterpolation struct {
	BaseNode
	Expr Expression
}

// Number literals

type NumberLiteral struct {
	TypedNode
	Value string
	Kind  NumberKind
}

type NumberKind int

const (
	Integer NumberKind = iota
	Float
	Hex
	Binary
	Octal
)

// Boolean literals

type BooleanLiteral struct {
	TypedNode
	Value bool
}

type NullLiteral struct {
	TypedNode
}

type VoidLiteral struct {
	TypedNode
}

// Collection literals

type ArrayLiteral struct {
	TypedNode
	Elements []Expression
}

type ObjectLiteral struct {
	TypedNode
	Fields []ObjectField
}

type ObjectField struct {
	BaseNode
	Name  ObjectFieldName
	Value Expression
}

type ObjectFieldName interface {
	Node
}

type ObjectFieldID struct {
	NamedNode
}

type ObjectFieldString struct {
	BaseNode
	Literal *StringLiteral
}

type MapLiteral struct {
	TypedNode
	Fields  []MapField
	IsEmpty bool
}

type MapField struct {
	BaseNode
	Key   Expression
	Value Expression
}

type SetLiteral struct {
	TypedNode
	Elements []Expression
}

// Tagged block strings

type TaggedBlockString struct {
	NamedNode
	Content      *StringLiteral
	InferredType Type
}

func (t *TaggedBlockString) SetInferredType(typ Type) {
	t.InferredType = typ
}
