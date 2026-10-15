// Package rt is the typed runtime generated Go programs link against. Every
// operation has a Go signature in terms of the program's own types: there is
// no interface-typed value ABI, no runtime type keys, and no boxing.
package rt

import (
	msruntime "github.com/manuscript-lang/manuscript/pkg/runtime"
)

// Execution carries cancellation, call depth, and the host roots of one
// running task.
type Execution = msruntime.Execution

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

// Fault raises a Manuscript fault with message.
func Fault(message string) { msruntime.Panic(message) }

// Seq is the identity; it marks an operand that must be evaluated before its
// siblings. Go orders calls, and Seq makes a plain read a call.
func Seq[T any](v T) T { return v }
