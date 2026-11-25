// conform: tags=testing,tier-stdlib
// conform: phase=check
import Data from "@std/core.ms"

fn need[T Data](value T) Int {
	return 1
}

export fn main() Int {
	ids := Set[Int]()
	return need(ids)
}
// expect-error: MS3000 11:12 Set[Int] does not satisfy Data; it is a Set or a Map whose key is not a String, which has no portable form; send a List, a Map[String, T], or a JsonValue object
