// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

enum Optional[T] {
	T
	null
}

fn wrong(value Int?) Int {
	return value or panic("called Optional.get() on null")
}
// expect-error: MS2001 5:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration
