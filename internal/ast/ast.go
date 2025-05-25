package ast

import "fmt"

// Position represents a source position
type Position struct {
	Line   int
	Column int
	Offset int
}

func (p Position) String() string {
	return fmt.Sprintf("%d:%d", p.Line, p.Column)
}

// Type represents a type in the type system
type Type interface {
	String() string                   // Human-readable representation
	Equals(other Type) bool           // Type equality check
	IsAssignableTo(other Type) bool   // Assignment compatibility
	IsCompatibleWith(other Type) bool // General compatibility
}

// BaseNode provides the common foundation for all AST nodes
type BaseNode struct {
	Position Position
}

func (n *BaseNode) Pos() Position {
	return n.Position
}

// NamedNode extends BaseNode for nodes that have names
type NamedNode struct {
	BaseNode
	Name string
}

// TypedNode extends BaseNode for nodes that can have inferred types
type TypedNode struct {
	BaseNode
	InferredType Type // Type inferred during type checking
}

func (n *TypedNode) GetInferredType() Type {
	return n.InferredType
}

func (n *TypedNode) SetInferredType(t Type) {
	n.InferredType = t
}

// Visitor interface for tree traversal
type Visitor interface {
	Visit(node Node) (visitor Visitor)
}

// Node is the base interface for all AST nodes
type Node interface {
	Pos() Position
}

// Declaration represents all top-level declarations
type Declaration interface {
	Node
}

// Statement represents all statements
type Statement interface {
	Node
}

// Expression represents all expressions
type Expression interface {
	Node
	GetInferredType() Type  // Get the inferred type
	SetInferredType(t Type) // Set the inferred type
}

// TypeAnnotation represents type annotations
type TypeAnnotation interface {
	Node
}

// Literal represents literal values
type Literal interface {
	Expression
}

// StringPart represents parts of string literals (content or interpolation)
type StringPart interface {
	Node
}
