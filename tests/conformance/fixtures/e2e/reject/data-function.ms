// conform: tags=testing,tier-stdlib
// conform: phase=check
import Data from "@std/core.ms"

type Handler {
	name String
	run fn() Int
}

fn need[T Data](value T) Int {
	return 1
}

export fn main() Int {
	return need(Handler("h", fn() Int => 1))
}
// expect-error: MS3000 15:12 Handler does not satisfy Data; field run is fn() Int, a function; send the data the function would compute
