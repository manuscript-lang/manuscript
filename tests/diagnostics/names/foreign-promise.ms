// conform: tags=diagnostics,stdlib-tasks,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
fn f() Void {
	p := Promise()
}
// expect-error: MS2001 5:10 unknown binding Promise; there is no free Promise: start concurrent work with promise(() => ...) from "@std/concurrency/promise.ms" and call wait() on the returned Promise
