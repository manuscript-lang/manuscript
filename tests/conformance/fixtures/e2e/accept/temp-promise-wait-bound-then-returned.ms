// conform: tags=cleanup,resources,promises
// conform: phase=run
// A promise made and awaited in one expression, its result bound and returned later, closes the promise once and keeps the result.
import promise from "@std/concurrency/promise.ms"

fn inner() Int!:
	return ok(7)

fn outer() Int!:
	r := promise(() => inner()).wait()
	return r

fn main() Void!:
	print(f"{outer()?}")
