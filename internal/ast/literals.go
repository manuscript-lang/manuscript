package ast

// String literals

type StringLiteral struct {
	TypedNode
	Parts []StringPart
	Kind  StringKind
}

func (l *StringLiteral) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, part := range l.Parts {
			part.Accept(v)
		}
	}
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

func (s *StringContent) Accept(v Visitor) {
	v.Visit(s)
}

type StringInterpolation struct {
	BaseNode
	Expr Expression
}

func (s *StringInterpolation) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		s.Expr.Accept(v)
	}
}

// Number literals

type NumberLiteral struct {
	TypedNode
	Value string
	Kind  NumberKind
}

func (l *NumberLiteral) Accept(v Visitor) {
	v.Visit(l)
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

func (l *BooleanLiteral) Accept(v Visitor) {
	v.Visit(l)
}

type NullLiteral struct {
	TypedNode
}

func (l *NullLiteral) Accept(v Visitor) {
	v.Visit(l)
}

type VoidLiteral struct {
	TypedNode
}

func (l *VoidLiteral) Accept(v Visitor) {
	v.Visit(l)
}

// Collection literals

type ArrayLiteral struct {
	TypedNode
	Elements []Expression
}

func (l *ArrayLiteral) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, elem := range l.Elements {
			elem.Accept(v)
		}
	}
}

type ObjectLiteral struct {
	TypedNode
	Fields []ObjectField
}

func (l *ObjectLiteral) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, field := range l.Fields {
			field.Accept(v)
		}
	}
}

type ObjectField struct {
	BaseNode
	Name  ObjectFieldName
	Value Expression // Optional, nil for shorthand
}

func (f *ObjectField) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		f.Name.Accept(v)
		if f.Value != nil {
			f.Value.Accept(v)
		}
	}
}

type ObjectFieldName interface {
	Node
}

type ObjectFieldID struct {
	NamedNode
}

func (n *ObjectFieldID) Accept(v Visitor) {
	v.Visit(n)
}

type ObjectFieldString struct {
	BaseNode
	Literal *StringLiteral
}

func (n *ObjectFieldString) Accept(v Visitor) {
	if v = v.Visit(n); v != nil {
		n.Literal.Accept(v)
	}
}

type MapLiteral struct {
	TypedNode
	Fields  []MapField
	IsEmpty bool // true for [:] empty map literal
}

func (l *MapLiteral) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, field := range l.Fields {
			field.Accept(v)
		}
	}
}

type MapField struct {
	BaseNode
	Key   Expression
	Value Expression
}

func (f *MapField) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		f.Key.Accept(v)
		f.Value.Accept(v)
	}
}

type SetLiteral struct {
	TypedNode
	Elements []Expression
}

func (l *SetLiteral) Accept(v Visitor) {
	if v = v.Visit(l); v != nil {
		for _, elem := range l.Elements {
			elem.Accept(v)
		}
	}
}

// Tagged block strings

type TaggedBlockString struct {
	NamedNode
	Content      *StringLiteral
	InferredType Type // Add explicit type field since NamedNode doesn't have it
}

func (t *TaggedBlockString) GetInferredType() Type {
	return t.InferredType
}

func (t *TaggedBlockString) SetInferredType(typ Type) {
	t.InferredType = typ
}

func (t *TaggedBlockString) Accept(v Visitor) {
	if v = v.Visit(t); v != nil {
		t.Content.Accept(v)
	}
}
