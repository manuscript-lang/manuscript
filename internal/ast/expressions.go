package ast

// Assignment expressions

type AssignmentExpr struct {
	TypedNode
	Left  Expression
	Op    AssignmentOp
	Right Expression
}

type AssignmentOp int

const (
	AssignEq AssignmentOp = iota
	AssignPlusEq
	AssignMinusEq
	AssignStarEq
	AssignSlashEq
	AssignModEq
	AssignCaretEq
)

// Ternary expression

type TernaryExpr struct {
	TypedNode
	Cond Expression
	Then Expression
	Else Expression
}

// Binary expressions

type BinaryExpr struct {
	TypedNode
	Left  Expression
	Op    BinaryOp
	Right Expression
}

type BinaryOp int

const (
	// Logical
	LogicalOr BinaryOp = iota
	LogicalAnd

	// Bitwise
	BitwiseXor
	BitwiseAnd

	// Equality
	Equal
	NotEqual

	// Comparison
	Less
	LessEqual
	Greater
	GreaterEqual

	// Arithmetic
	Add
	Subtract
	Multiply
	Divide
	Modulo
)

// Unary expressions

type UnaryExpr struct {
	TypedNode
	Op   UnaryOp
	Expr Expression
}

type UnaryOp int

const (
	UnaryPlus UnaryOp = iota
	UnaryMinus
	UnaryNot
)

// Postfix expressions

type CallExpr struct {
	TypedNode
	Func Expression
	Args []Expression
}

type DotExpr struct {
	TypedNode
	Expr  Expression
	Field string
}

type IndexExpr struct {
	TypedNode
	Expr  Expression
	Index Expression
}

// Primary expressions

type Identifier struct {
	NamedNode
	InferredType Type
}

func (e *Identifier) GetInferredType() Type {
	return e.InferredType
}

func (e *Identifier) SetInferredType(t Type) {
	e.InferredType = t
}

type ParenExpr struct {
	TypedNode
	Expr Expression
}

type VoidExpr struct {
	TypedNode
}

type NullExpr struct {
	TypedNode
}

// Try expression

type TryExpr struct {
	TypedNode
	Expr Expression
}

// Match expression

type MatchExpr struct {
	TypedNode
	Expr    Expression
	Cases   []CaseClause
	Default *DefaultClause
}

type CaseClause struct {
	BaseNode
	Pattern Expression
	Body    CaseBody
}

type DefaultClause struct {
	BaseNode
	Body CaseBody
}

type CaseBody interface {
	Node
}

type CaseExpr struct {
	TypedNode
	Expr Expression
}

type CaseBlock struct {
	BaseNode
	Block *CodeBlock
}

// Struct initialization

type StructInitExpr struct {
	NamedNode
	Fields       []StructField
	InferredType Type
}

func (e *StructInitExpr) GetInferredType() Type {
	return e.InferredType
}

func (e *StructInitExpr) SetInferredType(t Type) {
	e.InferredType = t
}

type StructField struct {
	NamedNode
	Value Expression
}
