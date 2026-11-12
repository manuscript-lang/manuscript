import (
	bit_and from "@std/math/math.ms",
	arguments from "@std/os/env.ms",
)

fn main() Unit:
	n := arguments()[0].parse_int().get()
	var cap = 1
	while cap < n * 2: cap *= 2

	mask := cap - 1
	var keys: List[Int] = [-1].repeated(cap)
	var vals: List[Int] = [0].repeated(cap)
	var random = 1

	for i in 0..n:
		random = (random * 1103515245 + 12345) % 2147483648

		k := random % 1000003
		var h = bit_and(k * 2654435761, mask)
		while keys[h] != -1 and keys[h] != k: h = bit_and(h + 1, mask)
		keys[h] = k
		vals[h] += 1

	var sum = 0

	for k in 0..n:
		var h = bit_and(k * 2654435761, mask)
		while keys[h] != -1 and keys[h] != k: h = bit_and(h + 1, mask)
		if keys[h] == k: sum += vals[h] * (k + 1)

	print("{sum}")
