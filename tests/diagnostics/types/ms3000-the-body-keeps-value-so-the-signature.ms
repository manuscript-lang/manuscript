// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn extract[T](hold value T?) &T {
	return value or panic("called Optional.get() on null")
}

export fn main() Int {
	return extract[Int](null)
}
// expect-error: MS3000 5:20 the body keeps `value`, so the signature must say so: write `move value Type`, or keep `.clone()` of it
