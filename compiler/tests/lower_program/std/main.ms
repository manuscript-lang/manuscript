import gcd, lcm from "@std/math/math.ms"

fn shout(n: Int) Int:
	return n * 2

fn main() Int:
	xs := [1, 2, 3]
	return shout(xs.length()) + gcd(12, 18) + lcm(4, 6)
