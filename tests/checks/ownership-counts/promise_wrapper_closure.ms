// expect-debug: allocs=26
// expect-release: allocs=26
// `promise(() => ...)` wraps the work in a closure that stores the result. The wrapper
// takes the work's captures and calls its code directly, so a start builds one closure
// object, not two: each promise past the first tables adds one allocation (20 promises:
// 20 closures and 6 blocks of the runtime's tables).
import promise from "@std/concurrency/promise.ms"

fn double(value Int) Int! {
	return ok(value * 2)
}

export fn main() Int {
	var total = 0

	for index in 0..20 {
		started := promise[Int](() => double(index))
		total += started.wait().get()
	}

	return total - 380
}
