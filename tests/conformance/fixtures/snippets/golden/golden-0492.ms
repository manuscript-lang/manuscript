// conform: tags=diagnostics
// conform: phase=check
enum Optional[T] {
	T
	null
}

fn wrong(value Int?) Result[Int, String] => ok_or(value, "missing")
// expect-error: MS2001 3:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration
