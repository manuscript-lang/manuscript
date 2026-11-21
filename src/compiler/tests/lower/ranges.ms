fn sum_to(n: Int) Int:
	var total = 0
	for i in 0..n:
		total += i
	return total

fn first_square_over(limit: Int) Int:
	for i in 1..1000:
		if i * i > limit: return i
	return 0

fn odd_total(n: Int) Int:
	var total = 0

	for i in 0..n:
		if i % 2 == 0: continue

		total += i

	return total

fn grid(rows: Int, cols: Int) Int:
	var cells = 0

	for r in 0..rows:
		for c in 0..cols:
			if c > r: break

			cells += 1

	return cells

fn main() Int:
	return sum_to(10) + first_square_over(50) + odd_total(9) + grid(4, 4)
