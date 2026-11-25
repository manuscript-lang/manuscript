// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
import Promise, promise from "@std/concurrency/promise.ms"

fn later() fn() Promise[Int] {
	xs := [1, 2, 3]
	return () => promise(() => ok(xs.length()))
}
// expect-error: MS3000 7:26 this closure outlives the statement but captures `xs`, which is borrowed, not owned; bind `own := xs.clone()` before the closure and capture `own` instead
