// conform: tags=diagnostics,stdlib-tasks,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
fn f() Void {
	spawn(() => 1)
}
// expect-error: MS2001 5:5 unknown binding spawn; there is no free spawn: start concurrent work with promise(fn: ...) from "@std/concurrency/promise.ms" and call wait() on the returned Promise
