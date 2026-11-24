// conform: tags=numbers,faults,stdlib-math,tier-stdlib
// conform: phase=run
// conform: origin=a negative shift count is checked in math.ms
import shift_left from "@std/math/math.ms"

fn main() Void {
	count := -1
	print(shift_left(1, count))
}
