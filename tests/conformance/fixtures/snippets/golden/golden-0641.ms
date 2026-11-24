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
