// Kind names shared by parsing, checking, lowering, and source tools.
package syntax

const (
	KindFn        = "fn"
	KindType      = "type"
	KindInterface = "interface"
	KindNative    = "native"
	KindImpl      = "impl"
	KindTest      = "test"
	KindBind      = "bind"
	KindAssign    = "assign"
	KindCall      = "call"
	KindReturn    = "return"
	KindBreak     = "break"
	KindContinue  = "continue"
	KindIf        = "if"
	KindWhile     = "while"
	KindFor       = "for"
	KindWith      = "with"
	KindMatch     = "match"
	KindNumber    = "number"
	KindBool      = "bool"
	KindUnit      = "unit"
	KindText      = "text"
	KindName      = "name"
	KindMember    = "member"
	KindApply     = "apply"
	KindIndex     = "index"
	KindList      = "list"
	KindUnary     = "unary"
	KindBinary    = "binary"
	KindLambda    = "lambda"
	KindRecord    = "record"
)

// StatementKinds enumerates executable nodes; repo-check verifies checker/lowering coverage.
func StatementKinds() []string {
	return []string{KindBind, KindAssign, KindCall, KindReturn, KindBreak, KindContinue, KindIf, KindWhile, KindFor, KindWith}
}

// ExpressionKinds enumerates executable nodes; repo-check verifies checker/lowering coverage.
func ExpressionKinds() []string {
	return []string{KindNumber, KindBool, KindUnit, KindText, KindName, KindMember, KindApply, KindCall, KindList, KindUnary, KindBinary, KindLambda, KindIndex, KindMatch}
}
