// conform: tags=alternatives,diagnostics,generics,optional,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:53 TestOptionalArgumentBoundaries
enum Optional[T] {
	T
	null
}

fn f(value Int?) Void => return

fn call() Void => f(4)
// expect-error: MS2001 4:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration
