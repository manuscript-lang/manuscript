// conform: tags=closures,control-flow,lists,tier-stdlib
// conform: phase=check
// A promise kept past the loop body reads `body` where it sits, so a binding that only
// borrows a list element ends before `running` does, like an owned local (#3845).
import Placement, Promise, PromiseOptions, promise from "@std/concurrency/promise.ms"

fn ten(k: Int) Int!:
	return ok(k * 10)

fn main() Int:
	var bodies = List[fn() Int!]()
	for k in 0..4:
		bodies.append(fn: ten(k))

	var running = List[Promise[Int]]()

	for k in 0..4:
		body := bodies[k]
		running.append(
			promise(
				fn: body(),
				options: PromiseOptions(placement: Placement.Spread)
			)
		)

	for r in running:
		print("{r.wait().get(-1)}")
	return 0
