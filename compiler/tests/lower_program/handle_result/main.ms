import BigInt, big_int_of_int from "@std/math/math.ms"

fn main() Int:
	a := big_int_of_int(2)
	b := big_int_of_int(3)
	if a.add(b).sign() == 0: return 1
	return 0
