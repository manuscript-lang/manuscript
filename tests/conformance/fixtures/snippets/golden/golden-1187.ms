// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn work(value Int?) Result[Int, Error] {
	return ok(value: value or panic("called Optional.get() on null"))
}
