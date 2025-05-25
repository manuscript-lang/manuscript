package ast

// Assignment expressions

type AssignmentExpr struct {
	TypedNode
	Left  Expression
	Op    AssignmentOp
	Right Expression
}

func (e *AssignmentExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Left.Accept(v)
		e.Right.Accept(v)
	}
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

func (e *TernaryExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Cond.Accept(v)
		e.Then.Accept(v)
		e.Else.Accept(v)
	}
}

// Binary expressions

type BinaryExpr struct {
	TypedNode
	Left  Expression
	Op    BinaryOp
	Right Expression
}

func (e *BinaryExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Left.Accept(v)
		e.Right.Accept(v)
	}
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

func (e *UnaryExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Expr.Accept(v)
	}
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

func (e *CallExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Func.Accept(v)
		for _, arg := range e.Args {
			arg.Accept(v)
		}
	}
}

type DotExpr struct {
	TypedNode
	Expr  Expression
	Field string
}

func (e *DotExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Expr.Accept(v)
	}
}

type IndexExpr struct {
	TypedNode
	Expr  Expression
	Index Expression
}

func (e *IndexExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Expr.Accept(v)
		e.Index.Accept(v)
	}
}

// Primary expressions

type Identifier struct {
	NamedNode
	InferredType Type // Add explicit type field since NamedNode doesn't have it
}

func (e *Identifier) GetInferredType() Type {
	return e.InferredType
}

func (e *Identifier) SetInferredType(t Type) {
	e.InferredType = t
}

func (e *Identifier) Accept(v Visitor) {
	v.Visit(e)
}

type ParenExpr struct {
	TypedNode
	Expr Expression
}

func (e *ParenExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Expr.Accept(v)
	}
}

type VoidExpr struct {
	TypedNode
}

func (e *VoidExpr) Accept(v Visitor) {
	v.Visit(e)
}

type NullExpr struct {
	TypedNode
}

func (e *NullExpr) Accept(v Visitor) {
	v.Visit(e)
}

// Try expression

type TryExpr struct {
	TypedNode
	Expr Expression
}

func (e *TryExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Expr.Accept(v)
	}
}

// Match expression

type MatchExpr struct {
	TypedNode
	Expr    Expression
	Cases   []CaseClause
	Default *DefaultClause // Optional, nil if no default
}

func (e *MatchExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		e.Expr.Accept(v)
		for _, c := range e.Cases {
			c.Accept(v)
		}
		if e.Default != nil {
			e.Default.Accept(v)
		}
	}
}

type CaseClause struct {
	BaseNode
	Pattern Expression
	Body    CaseBody
}

func (c *CaseClause) Accept(v Visitor) {
	if v = v.Visit(c); v != nil {
		c.Pattern.Accept(v)
		c.Body.Accept(v)
	}
}

type DefaultClause struct {
	BaseNode
	Body CaseBody
}

func (c *DefaultClause) Accept(v Visitor) {
	if v = v.Visit(c); v != nil {
		c.Body.Accept(v)
	}
}

type CaseBody interface {
	Node
}

type CaseExpr struct {
	TypedNode
	Expr Expression
}

func (c *CaseExpr) Accept(v Visitor) {
	if v = v.Visit(c); v != nil {
		c.Expr.Accept(v)
	}
}

type CaseBlock struct {
	BaseNode
	Block *CodeBlock
}

func (c *CaseBlock) Accept(v Visitor) {
	if v = v.Visit(c); v != nil {
		c.Block.Accept(v)
	}
}

// Struct initialization

type StructInitExpr struct {
	NamedNode
	Fields       []StructField
	InferredType Type // Add explicit type field since NamedNode doesn't have it
}

func (e *StructInitExpr) GetInferredType() Type {
	return e.InferredType
}

func (e *StructInitExpr) SetInferredType(t Type) {
	e.InferredType = t
}

func (e *StructInitExpr) Accept(v Visitor) {
	if v = v.Visit(e); v != nil {
		for _, field := range e.Fields {
			field.Accept(v)
		}
	}
}

type StructField struct {
	NamedNode
	Value Expression
}

func (f *StructField) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		f.Value.Accept(v)
	}
}
