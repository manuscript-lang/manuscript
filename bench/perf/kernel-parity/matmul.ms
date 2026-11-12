import (
	arguments from "@std/os/env.ms",
)

fn main() Unit:
	n := arguments()[0].parse_int().get()
	var a: List[Int] = [0].repeated(n * n)
	var b: List[Int] = [0].repeated(n * n)
	var c: List[Int] = [0].repeated(n * n)
	for i in 0..n * n:
		a[i] = i % 7
		b[i] = i % 5
	for i in 0..n:
		for k in 0..n:
			x := a[i * n + k]
			for j in 0..n: c[i * n + j] = c[i * n + j] + x * b[k * n + j]
	var sum = 0
	for i in 0..n * n: sum += c[i] * (i % 13 + 1)
	print("{sum}")
