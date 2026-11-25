// conform: tags=numbers,faults,stdlib-math,tier-stdlib
// conform: phase=run
// conform: origin=a negative shift count is checked in math.ms
import shift_left from "@std/math/math.ms"

fn main() Void {
	count := -1
	print(shift_left(1, count))
}
// expect-exit: 134
// expect-stderr: shift_left: count must not be negative, found -1
// expect-stderr:   at @std/math/math.ms:<LINE> in check_shift_count
// expect-stderr:   at @std/math/math.ms:<LINE> in shift_left
// expect-stderr:   at fault-shift-count.ms:8 in main
