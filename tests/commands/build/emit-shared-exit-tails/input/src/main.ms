import (BigInt, big_int_of_int from "@std/math/math.ms")

// Every call below can fault, so each one is followed by an exit that drops `a` and `b`; the exits are one block.
fn main() Void {
	a := big_int_of_int(1)
	b := big_int_of_int(2)
	print(a.add(b).to_string())
	print(a.add(b).to_string())
	print(a.add(b).to_string())
	print(a.add(b).to_string())
}
