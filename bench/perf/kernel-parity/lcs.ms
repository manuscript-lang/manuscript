import arguments from "@std/os/env.ms"

fn main() Unit:
	n := arguments()[0].parse_int().get()
	var random = 1
	var s: List[Int] = []
	var t: List[Int] = []

	for i in 0..n:
		random = (random * 1103515245 + 12345) % 2147483648
		s.append(random % 4)

	for i in 0..n:
		random = (random * 1103515245 + 12345) % 2147483648
		t.append(random / 16 % 4)

	var prev: List[Int] = [0].repeated(n + 1)
	var cur: List[Int] = [0].repeated(n + 1)

	for i in 1..n + 1:
		for j in 1..n + 1:
			cur[j] = (
				if s[i - 1] == t[j - 1]: prev[j - 1] + 1 else: (
					if prev[j] > cur[j - 1]: prev[j] else: cur[
						j - 1
					]
				)
			)

		tmp := prev
		prev = cur
		cur = tmp

	print("{prev[n]}")
