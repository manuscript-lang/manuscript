// Package ir is the checked, desugared form of Manuscript expressions that
// lowering consumes. Elaboration reads the syntax tree and the checked program
// once; a node then carries every fact lowering needs, so lowering does not
// classify spelling or consult checker tables.
//
// The package is being adopted one expression form at a time. An operand that
// has no node yet is a Deferred, which lowering still reads from syntax.
package ir

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Expr is an elaborated expression.
type Expr interface{ expr() }

// Deferred is an operand not yet represented in the IR. Lowering evaluates it
// from its syntax, including checked boundary conversions.
type Deferred struct{ Source *syntax.Expression }

// Converted is a value at an explicit checked use boundary. It retains the
// source expression and conversion order even while its body remains Deferred.
type Converted struct{ Use Edge }

// IntLiteral is a signed 64-bit integer literal.
type IntLiteral struct {
	Value int64
	Type  *checker.Type
	// Unary retains the existing conservative Debug table policy. Release
	// constant tables can consume this already elaborated value.
	Unary bool
}

// FloatLiteral is a 64-bit floating-point literal.
type FloatLiteral struct {
	Value float64
	Type  *checker.Type
	Unary bool
}

// DecimalLiteral is a decimal literal; Text keeps the written digits and suffix.
type DecimalLiteral struct {
	Text string
	Type *checker.Type
}

// BoolLiteral is true or false.
type BoolLiteral struct {
	Value bool
	Type  *checker.Type
}

// UnitLiteral is the Unit value.
type UnitLiteral struct{}

// Text is a string literal with interpolated operands. A part is either fixed
// text or a Value to format.
type Text struct {
	Parts []TextPart
	Type  *checker.Type
}

// TextPart is fixed text when Value is nil, otherwise an interpolated operand.
type TextPart struct {
	Text  string
	Value Expr
}

// List constructs a list of the given checked type.
type List struct {
	Type  *checker.Type
	Items []Expr
	// Elements parallels Items with source/expected/coercion facts for consumers
	// that choose a typed constructor or initialization ABI.
	Elements []Edge
}

// Map constructs a map of the given checked type. Pos is the construction
// site reported on failure.
type Map struct {
	Pos     syntax.Position
	Type    *checker.Type
	Entries []Entry
}

// Entry is one key and value of a Map, evaluated in written order.
type Entry struct{ Key, Value Expr }

func (Deferred) expr()       {}
func (Converted) expr()      {}
func (IntLiteral) expr()     {}
func (FloatLiteral) expr()   {}
func (DecimalLiteral) expr() {}
func (BoolLiteral) expr()    {}
func (UnitLiteral) expr()    {}
func (Text) expr()           {}
func (List) expr()           {}
func (Map) expr()            {}
