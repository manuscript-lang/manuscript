// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn extract[T](value T?) T {
	return value or panic("called Optional.get() on null")
}

export fn main() Int {
	return extract[Int](null)
}
