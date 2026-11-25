// conform: tags=testing,tier-core
// conform: phase=check
import Source from "@std/io/io.ms"

type Counted {
	log String
}

// `next` returns Int?, not Int?!, so Counted is not a Source[Int].
fn var Counted.next() Int? {
	return null
}

fn move Counted.close() Void! {
	return ok()
}

fn drain(s Source[Int]) Int {
	return 1
}

fn main() Void {
	drain(Counted("x"))
}
// expect-error: MS3001 23:11 expected Source[Int], found Counted (in argument 's' of drain); Counted does not satisfy Source[Int] by its own methods (next must be declared as fn next() Int?!); declare each operation as a method of Counted with the interface's exact signature
