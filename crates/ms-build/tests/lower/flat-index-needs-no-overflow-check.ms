// expect-opt-mir-absent: "iadd.chk"
// A row-major index `i * n + j` with `i, j < n` stays below the checked square `n * n`, so
// neither the product nor the sum can overflow.
import arguments from "@std/os/env.ms"

fn main() Unit:
	n := arguments()[0].parse_int().get()
	var c: List[Int] = [0].repeated(n * n)

	for i in 0..n:
		for j in 0..n: c[i * n + j] = i
	print("{c[0]}")
