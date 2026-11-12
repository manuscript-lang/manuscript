type Stat:
	count: Int
	sum: Int
	max: Int

fn main() Unit:
	var stats: Map[Int, Stat] = {}
	var x = 12345

	for i in 0..2000000:
		x = (x * 1103515245 + 12345) % 2147483648

		k := x % 1000
		v := i % 100
		stats.update(k, Stat(0, 0, 0), fn s: Stat(s.count + 1, s.sum + v, s.max.max(v)))

	var t = 0
	for e in stats.entries():
		t += e.value.count + e.value.sum + e.value.max
	print("{t}")
