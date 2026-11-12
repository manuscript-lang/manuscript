fn main() Unit:
	var counts: Map[Int, Int] = {}
	var x = 12345

	for i in 0..2000000:
		x = (x * 1103515245 + 12345) % 2147483648

		k := x % 50000
		counts[k] = counts.get(k).get(0) + 1

	var best = 0
	var hits = 0

	for i in 0..2000000:
		x = (x * 1103515245 + 12345) % 2147483648
		if counts.contains(x % 100000): hits += 1

	for e in counts.entries():
		if e.value > best: best = e.value
	print("{counts.length()} {best} {hits}")
