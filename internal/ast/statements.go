package ast

// Statement implementations

type ExprStmt struct {
	BaseNode
	Expr Expression
}

type ReturnStmt struct {
	BaseNode
	Values []Expression // Optional, nil for bare return
}

type YieldStmt struct {
	BaseNode
	Values []Expression // Optional, nil for bare yield
}

type DeferStmt struct {
	BaseNode
	Expr Expression
}

type AsyncStmt struct {
	BaseNode
	Expr Expression
}

type GoStmt struct {
	BaseNode
	Expr Expression
}

type BreakStmt struct {
	BaseNode
}

type ContinueStmt struct {
	BaseNode
}

type CheckStmt struct {
	BaseNode
	Expr    Expression
	Message string // Error message as string literal
}

type TryStmt struct {
	BaseNode
	Expr Expression
}

// Control Flow Statements

type IfStmt struct {
	BaseNode
	Cond Expression
	Then *CodeBlock
	Else *CodeBlock // Optional, nil if no else clause
}

type ForStmt struct {
	BaseNode
	Loop ForLoop
}

type ForLoop interface {
	Node
}

type ForTrinityLoop struct {
	BaseNode
	Init ForInit    // Optional, nil if empty
	Cond Expression // Optional, nil if empty
	Post Expression // Optional, nil if empty
	Body *LoopBody
}

type ForInLoop struct {
	BaseNode
	Key      string // Optional, empty if no key
	Value    string // The value variable
	Iterable Expression
	Body     *LoopBody
}

type ForInit interface {
	Node
}

type ForInitLet struct {
	BaseNode
	Let *LetSingle
}

type WhileStmt struct {
	BaseNode
	Cond Expression
	Body *LoopBody
}

// Block types

type CodeBlock struct {
	BaseNode
	Stmts []Statement
}

type LoopBody struct {
	BaseNode
	Stmts []Statement
}

// Piped Statements

type PipedStmt struct {
	BaseNode
	Calls []PipedCall
}

type PipedCall struct {
	BaseNode
	Expr Expression
	Args []PipedArg
}

type PipedArg struct {
	NamedNode
	Value Expression
}
