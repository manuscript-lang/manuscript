fn sum_to(n: Int) Int:
	var total = 0
	var i = 0

	while i < n:
		total += i
		i += 1

	return total

fn first_over(limit: Int) Int:
	var n = 1

	while true:
		if n * n > limit: break

		n += 1

	return n

fn skip_even(n: Int) Int:
	var total = 0
	var i = 0

	while i < n:
		i += 1
		if i % 2 == 0: continue

		total += i

	return total

fn collatz(start: Int) Int:
	var n = start
	var steps = 0

	while n != 1:
		if n % 2 == 0:
			n /= 2
		else:
			n = 3 * n + 1

		steps += 1
		if steps > 200: break

	return steps

fn main() Int:
	return sum_to(10) + first_over(50) + skip_even(9) + collatz(7)
