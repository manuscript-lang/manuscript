fn add(a: Int, b: Int) Int:
	return a + b

fn twice(a: Int) Int:
	return add(a, a)

fn fib(n: Int) Int:
	if n < 2: return n
	return fib(n - 1) + fib(n - 2)

fn even(n: Int) Bool:
	if n == 0: return true
	return odd(n - 1)

fn odd(n: Int) Bool:
	if n == 0: return false
	return even(n - 1)

fn scale(x: Float, k: Float) Float:
	return x * k

fn main() Int:
	if even(10) and scale(1.5, 2.0) > 2.0: return twice(3) + fib(10)
	return add(1, 2)
