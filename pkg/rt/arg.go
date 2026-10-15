package rt

// Arg is an argument of a parameter that has a default. A function that
// declares defaults takes its defaulted parameters as Arg and fills the absent
// ones in its own prologue, in its own scope, so the default of a function
// value is the default of the function it came from.
type Arg[T any] struct {
	Val T
	Set bool
}

// Given is a supplied argument.
func Given[T any](v T) Arg[T] { return Arg[T]{Val: v, Set: true} }
