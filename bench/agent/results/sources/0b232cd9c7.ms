import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn rng(s: Int, l: Int) String:
	if l == 1: return "{s}"
	return "{s},{l}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var all = List[String]()
	for line in lines(stdin()):
		all.append(line.clone())
	head := all.get(0, "").split(" ")
	name_a := head.get(0, "")
	name_b := head.get(1, "")
	ctx := head.get(2, "0").parse_int().get(0)
	n := head.get(3, "0").parse_int().get(0)
	m := head.get(4, "0").parse_int().get(0)
	var a = List[String]()
	var b = List[String]()
	for i in 0..n:
		a.append(all.get(1 + i, "").clone())
	for j in 0..m:
		b.append(all.get(1 + n + j, "").clone())
	w := m + 1
	var tab = List[Int]()
	for _k in 0..((n + 1) * w):
		tab.append(0)
	var i = n - 1
	while i >= 0:
		var j = m - 1
		while j >= 0:
			if a.get(i, "") == b.get(j, ""):
				tab[i * w + j] = tab.get((i + 1) * w + j + 1, 0) + 1
			else:
				x := tab.get((i + 1) * w + j, 0)
				y := tab.get(i * w + j + 1, 0)
				tab[i * w + j] = if x >= y: x else: y
			j -= 1
		i -= 1
	var kinds = List[Int]()
	var texts = List[String]()
	var p = 0
	var q = 0
	while p < n or q < m:
		if p < n and q < m and a.get(p, "") == b.get(q, ""):
			kinds.append(0)
			texts.append(a.get(p, "").clone())
			p += 1
			q += 1
		else if q == m or (p < n and tab.get((p + 1) * w + q, 0) >= tab.get(p * w + q + 1, 0)):
			kinds.append(1)
			texts.append(a.get(p, "").clone())
			p += 1
		else:
			kinds.append(2)
			texts.append(b.get(q, "").clone())
			q += 1
	var changes = List[Int]()
	for k in 0..kinds.length():
		if kinds.get(k, 0) != 0: changes.append(k)
	if changes.length() == 0: return ok(unit)
	var out = "--- {name_a}\n+++ {name_b}\n"
	total := kinds.length()
	var ci = 0
	while ci < changes.length():
		first := changes.get(ci, 0)
		var last = first
		var cj = ci + 1
		while cj < changes.length() and changes.get(cj, 0) - last - 1 <= 2 * ctx:
			last = changes.get(cj, 0)
			cj += 1
		var s = first - ctx
		if s < 0: s = 0
		var e = last + ctx
		if e > total - 1: e = total - 1
		var before_a = 0
		var before_b = 0
		for k in 0..s:
			if kinds.get(k, 0) != 2: before_a += 1
			if kinds.get(k, 0) != 1: before_b += 1
		var la = 0
		var lb = 0
		var body = ""
		for k in s..(e + 1):
			kd := kinds.get(k, 0)
			if kd != 2: la += 1
			if kd != 1: lb += 1
			pre := if kd == 0: " " else if kd == 1: "-" else: "+"
			body = "{body}{pre}{texts.get(k, "")}\n"
		sa := before_a + (if la > 0: 1 else: 0)
		sb := before_b + (if lb > 0: 1 else: 0)
		out = "{out}@@ -{rng(sa, la)} +{rng(sb, lb)} @@\n{body}"
		ci = cj
	print(out, end: "")
	return ok(unit)
