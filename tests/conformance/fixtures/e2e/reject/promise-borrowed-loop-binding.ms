// conform: tags=closures,control-flow,lists,tier-stdlib
// conform: phase=check
// A promise kept past the loop body owns what it captures, because it is not waited in the
// round: `body` is a function value, which is shared, so the promise gets its own copy (#3845).
import Placement, Promise, PromiseOptions, promise from "@std/concurrency/promise.ms"

fn ten(k Int) Int!:
	return ok(k * 10)

fn main() Int:
	var bodies = List[fn() Int!]()
	for k in 0..4:
		bodies.append(() => ten(k))

	var running = List[Promise[Int]]()

	for k in 0..4:
		body := bodies[k]
		running.append(
			promise(
				() => body(),
				options: PromiseOptions(placement: Placement.Spread)
			)
		)

	for r in running:
		print(f"{r.wait().get_or(-1)}")
	return 0
