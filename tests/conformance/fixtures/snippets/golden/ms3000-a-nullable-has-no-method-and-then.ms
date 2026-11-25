// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn crash(value Int) Int? {
	return (1 / value)
}

export fn main() Int {
	value Int? := 0
	return value.and_then(crash) or panic("called Optional.get() on null")
}
// expect-error: MS3000 11:18 a nullable has no method `and_then`; write `if x != null { ... }` and use `x`
