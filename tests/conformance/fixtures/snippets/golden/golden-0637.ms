// conform: tags=diagnostics
// conform: phase=check
enum Optional[T] {
	T
	null
}

fn f(value Int?) Void => return

fn call() Void => f(4)
// expect-error: MS2001 3:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration
