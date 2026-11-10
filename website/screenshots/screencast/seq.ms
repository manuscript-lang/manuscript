fn fib(n: Int) Int:
	return if n < 2: n else: fib(n - 1) + fib(n - 2)

fn main() Unit:
	results := [36, 36, 36, 36].map(fn n: fib(n))
	print(results.length())
