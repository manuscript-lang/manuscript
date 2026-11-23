// conform: tags=testing,tier-core
// conform: phase=check
import Source from "@std/io/io.ms"

type Counted:
	log: String

// `next` returns Int?, not Int?!, so Counted is not a Source[Int].
fn var Counted.next() Int?:
	return null

fn move Counted.close() Void!:
	return ok()

fn drain(s: Source[Int]) Int:
	return 1

fn main() Void:
	drain(Counted("x"))
