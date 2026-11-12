import (
	arguments from "@std/os/env.ms",
)

fn main() Unit:
	n := arguments()[0].parse_int().get()
	var a: List[Int] = []
	var random = 1
	for i in 0..n:
		random = (random * 1103515245 + 12345) % 2147483648
		a.append(random % 100003)
	var i = 0
	while i < n:
		end := if i + 16 < n: i + 16 else: n
		for j in i + 1..end:
			x := a[j]
			var k = j
			while k > i and a[k - 1] > x:
				a[k] = a[k - 1]
				k -= 1
			a[k] = x
		i += 16
	var b: List[Int] = [0].repeated(n)
	var w = 16
	while w < n:
		var lo = 0
		while lo < n:
			mid := if lo + w < n: lo + w else: n
			hi := if lo + 2 * w < n: lo + 2 * w else: n
			var p = lo
			var q = mid
			var o = lo
			while p < mid and q < hi:
				if a[q] < a[p]:
					b[o] = a[q]
					q += 1
				else:
					b[o] = a[p]
					p += 1
				o += 1
			while p < mid:
				b[o] = a[p]
				p += 1
				o += 1
			while q < hi:
				b[o] = a[q]
				q += 1
				o += 1
			lo += 2 * w
		t := a
		a = b
		b = t
		w *= 2
	var sum = 0
	for x in 0..n: sum += (a[x] + 1) * (x + 1)
	print("{sum}")
