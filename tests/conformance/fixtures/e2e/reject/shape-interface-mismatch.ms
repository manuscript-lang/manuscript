// conform: tags=testing,tier-core
// conform: phase=check
import Source from "@std/io/io.ms"

type Counted:
	log: String

// `next` returns Int?, not Int?!, so Counted is not a Source[Int].
fn var Counted.next() Int?:
	return none

fn var Counted.close() Unit!:
	return ok(unit)

fn drain(s: Source[Int]) Int:
	return 1

fn main() Unit:
	drain(Counted("x"))
