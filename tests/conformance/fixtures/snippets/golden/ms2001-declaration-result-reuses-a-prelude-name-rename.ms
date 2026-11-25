// conform: tags=diagnostics
// conform: phase=check
enum Result[T, E] {
	ok(value T)
	error(cause E)
}

fn wrong(value Result[Int, String]) Int? => value.to_optional()
// expect-error: MS2001 3:1 declaration Result reuses a prelude name; rename it, because Result always refers to the standard declaration
