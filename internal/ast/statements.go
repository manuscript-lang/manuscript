package ast

// Statement implementations

type ExprStmt struct {
	BaseNode
	Expr Expression
}

func (s *ExprStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		s.Expr.Accept(v)
	}
}

type ReturnStmt struct {
	BaseNode
	Values []Expression // Optional, nil for bare return
}

func (s *ReturnStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		for _, val := range s.Values {
			val.Accept(v)
		}
	}
}

type YieldStmt struct {
	BaseNode
	Values []Expression // Optional, nil for bare yield
}

func (s *YieldStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		for _, val := range s.Values {
			val.Accept(v)
		}
	}
}

type DeferStmt struct {
	BaseNode
	Expr Expression
}

func (s *DeferStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		s.Expr.Accept(v)
	}
}

type BreakStmt struct {
	BaseNode
}

func (s *BreakStmt) Accept(v Visitor) {
	v.Visit(s)
}

type ContinueStmt struct {
	BaseNode
}

func (s *ContinueStmt) Accept(v Visitor) {
	v.Visit(s)
}

type CheckStmt struct {
	BaseNode
	Expr    Expression
	Message string // Error message as string literal
}

func (s *CheckStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		s.Expr.Accept(v)
	}
}

type TryStmt struct {
	BaseNode
	Expr Expression
}

func (s *TryStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		s.Expr.Accept(v)
	}
}

// Control Flow Statements

type IfStmt struct {
	BaseNode
	Cond Expression
	Then *CodeBlock
	Else *CodeBlock // Optional, nil if no else clause
}

func (s *IfStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		s.Cond.Accept(v)
		s.Then.Accept(v)
		if s.Else != nil {
			s.Else.Accept(v)
		}
	}
}

type ForStmt struct {
	BaseNode
	Loop ForLoop
}

func (s *ForStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		s.Loop.Accept(v)
	}
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

func (f *ForTrinityLoop) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		if f.Init != nil {
			f.Init.Accept(v)
		}
		if f.Cond != nil {
			f.Cond.Accept(v)
		}
		if f.Post != nil {
			f.Post.Accept(v)
		}
		f.Body.Accept(v)
	}
}

type ForInLoop struct {
	BaseNode
	Key      string // Optional, empty if no key
	Value    string // The value variable
	Iterable Expression
	Body     *LoopBody
}

func (f *ForInLoop) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		f.Iterable.Accept(v)
		f.Body.Accept(v)
	}
}

type ForInit interface {
	Node
}

type ForInitLet struct {
	BaseNode
	Let *LetSingle
}

func (f *ForInitLet) Accept(v Visitor) {
	if v = v.Visit(f); v != nil {
		f.Let.Accept(v)
	}
}

type WhileStmt struct {
	BaseNode
	Cond Expression
	Body *LoopBody
}

func (s *WhileStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		s.Cond.Accept(v)
		s.Body.Accept(v)
	}
}

// Block types

type CodeBlock struct {
	BaseNode
	Stmts []Statement
}

func (b *CodeBlock) Accept(v Visitor) {
	if v = v.Visit(b); v != nil {
		for _, stmt := range b.Stmts {
			stmt.Accept(v)
		}
	}
}

type LoopBody struct {
	BaseNode
	Stmts []Statement
}

func (b *LoopBody) Accept(v Visitor) {
	if v = v.Visit(b); v != nil {
		for _, stmt := range b.Stmts {
			stmt.Accept(v)
		}
	}
}

// Piped Statements

type PipedStmt struct {
	BaseNode
	Calls []PipedCall
}

func (s *PipedStmt) Accept(v Visitor) {
	if v = v.Visit(s); v != nil {
		for _, call := range s.Calls {
			call.Accept(v)
		}
	}
}

type PipedCall struct {
	BaseNode
	Expr Expression
	Args []PipedArg
}

func (c *PipedCall) Accept(v Visitor) {
	if v = v.Visit(c); v != nil {
		c.Expr.Accept(v)
		for _, arg := range c.Args {
			arg.Accept(v)
		}
	}
}

type PipedArg struct {
	NamedNode
	Value Expression
}

func (a *PipedArg) Accept(v Visitor) {
	if v = v.Visit(a); v != nil {
		a.Value.Accept(v)
	}
}
