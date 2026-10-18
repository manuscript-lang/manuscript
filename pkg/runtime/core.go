// Package rt is the typed runtime generated Go programs link against. Every
// operation has a Go signature in terms of the program's own types: there is
// no interface-typed value ABI, no runtime type keys, and no boxing.
package msruntime

// Unit is the only value of the Unit type.
type Unit = struct{}

// Option is a checked Optional[T]; Val is meaningful only when Some.
type Option[T any] struct {
	Val  T
	Some bool
}

// Some returns an Option holding v.
func Some[T any](v T) Option[T] { return Option[T]{Val: v, Some: true} }

// None returns the empty Option.
func None[T any]() Option[T] { return Option[T]{} }

// Result is a checked Result[T, E]; Err is meaningful only when Failed.
type Result[T, E any] struct {
	Val    T
	Err    E
	Failed bool
}

// Ok returns a successful Result.
func Ok[T, E any](v T) Result[T, E] { return Result[T, E]{Val: v} }

// Fail returns a failed Result.
func Fail[T, E any](e E) Result[T, E] { return Result[T, E]{Err: e, Failed: true} }

// Eq is the equality of T that a native operation needs when T is not a Go
// comparable type or has an explicit Equal implementation. The program passes
// the equality it generated; Go-comparable types use Equals.
type Eq[T any] = func(*Execution, T, T) bool

// Cmp orders two values: negative, zero or positive.
type Cmp[T any] = func(*Execution, T, T) int

// Seq is the identity; it marks an operand that must be evaluated before its
// siblings. Go orders calls, and Seq makes a plain read a call.
func Seq[T any](v T) T { return v }

// Zero is the zero value of T.
func Zero[T any]() T {
	var zero T
	return zero
}

// Unreachable marks code a checked program cannot reach.
func Unreachable() { Raise("runtime invariant: unreachable") }

// Panic is the standard faults.panic operation.
func Panic(_ *Execution, message string) Unit {
	Raise(message)
	return Unit{}
}

// Equal and Hashable are the standard contracts a program may implement for
// its own types. A value of contract type Equal is a generated view that
// forwards to the implementation.
type Equal interface {
	Equals(*Execution, Equal) bool
}

// Unview returns the concrete value a contract view wraps, for a native
// operation whose argument has the receiver's own type.
func Unview[T any](v any) T {
	if r, ok := v.(interface{ Receiver() any }); ok {
		v = r.Receiver()
	}
	t, ok := v.(T)
	if !ok {
		Raise("operands have different types")
	}
	return t
}

// Comparable orders a value against another in the same domain.
type Comparable interface {
	Compare(*Execution, Comparable) int
}

type Hashable interface {
	Hash(*Execution) int
}
