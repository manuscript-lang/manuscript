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

// IntLiteral is a signed 64-bit integer literal.
type IntLiteral struct {
	Value int64
	Type  *checker.Type
}

// FloatLiteral is a 64-bit floating-point literal.
type FloatLiteral struct {
	Value float64
	Type  *checker.Type
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

// Local reads a local binding.
type Local struct {
	Binding *checker.Binding
	Type    *checker.Type
}

// Unary applies a prefix operator other than try. Pos is the site reported
// when the operation fails.
type Unary struct {
	Pos     syntax.Position
	Op      string
	Operand Expr
	Type    *checker.Type
}

// Binary applies an infix operator. LeftType and RightType are the checked
// types of the operands, which select the operation lowering emits.
type Binary struct {
	Pos                 syntax.Position
	Op                  string
	Left, Right         Expr
	LeftType, RightType *checker.Type
	Type                *checker.Type
}

// Member reads a member of Receiver: a record field, an alternative case, a
// bound or native method, or a native property. Info holds the checker's
// resolution of the member, which selects what lowering emits.
type Member struct {
	Pos          syntax.Position
	Receiver     Expr
	ReceiverPos  syntax.Position
	ReceiverType *checker.Type
	Name         string
	Info         *checker.Info
}

// Argument is one call argument. Optional is the Optional type a plain value
// is wrapped into when the parameter accepts one.
type Argument struct {
	Pos      syntax.Position
	Name     string
	Value    Expr
	Type     *checker.Type
	Optional *checker.Type
}

// Call invokes Callee with Args, which are in the order the checker settled
// on. A member callee is a Member, so its receiver and resolution are on the
// node. Info holds the checker's facts for the call, including its result type
// and whether it builds a record or alternative case.
type Call struct {
	Pos        syntax.Position
	Callee     Expr
	CalleePos  syntax.Position
	CalleeType *checker.Type
	Args       []Argument
	Info       *checker.Info
}

// View converts Receiver to a contract view of its static type.
type View struct {
	Receiver     Expr
	ReceiverType *checker.Type
	Type         *checker.Type
}

func (Deferred) expr()       {}
func (Call) expr()           {}
func (View) expr()           {}
func (Member) expr()         {}
func (Local) expr()          {}
func (Unary) expr()          {}
func (Binary) expr()         {}
func (IntLiteral) expr()     {}
func (FloatLiteral) expr()   {}
func (DecimalLiteral) expr() {}
func (BoolLiteral) expr()    {}
func (UnitLiteral) expr()    {}
func (Text) expr()           {}
func (List) expr()           {}
func (Map) expr()            {}
