import stdin from "@std/io/io.ms"
import lines, collect from "@std/io/streams.ms"

fn rng(s: Int, l: Int) String:
	if l == 1: return "{s}"
	return "{s},{l}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	all := lines(stdin()) | collect(none)?
	head := all.get(0, "").split(" ")
	na := head.get(1, "")
	nb := head.get(2, "")
	ctx := head.get(2, "0").parse_int().get(0)
	n := head.get(3, "0").parse_int().get(0)
	m := head.get(4, "0").parse_int().get(0)
	_ := na
	_ := nb
	var a = List[String]()
	var b = List[String]()
	for i in 0..n:
		a.append(all.get(1 + i, ""))
	for j in 0..m:
		b.append(all.get(1 + n + j, ""))
	w := m + 1
	var t = List[Int]()
	for _k in 0..((n + 1) * w):
		t.append(0)
	var i = n - 1
	while i >= 0:
		var j = m - 1
		while j >= 0:
			if a.get(i, "") == b.get(j, ""):
				t[i * w + j] = t.get((i + 1) * w + j + 1, 0) + 1
			else:
				d := t.get((i + 1) * w + j, 0)
				e := t.get(i * w + j + 1, 0)
				t[i * w + j] = if d >= e: d else: e
			j -= 1
		i -= 1
	// script
	var kind = List[Int]()
	var text = List[String]()
	var ai = List[Int]()
	var bi = List[Int]()
	var x = 0
	var y = 0
	while x < n or y < m:
		ai.append(x)
		bi.append(y)
		if x < n and y < m and a.get(x, "") == b.get(y, ""):
			kind.append(0)
			text.append(a.get(x, ""))
			x += 1
			y += 1
		else if y == m or (x < n and t.get((x + 1) * w + y, 0) >= t.get(x * w + y + 1, 0)):
			kind.append(1)
			text.append(a.get(x, ""))
			x += 1
		else:
			kind.append(2)
			text.append(b.get(y, ""))
			y += 1
	total := kind.length()
	var changes = List[Int]()
	for k in 0..total:
		if kind.get(k, 0) != 0: changes.append(k)
	if changes.length() == 0: return ok(unit)
	print("--- {head.get(0, "")}")
	print("+++ {head.get(1, "")}")
	var g = 0
	while g < changes.length():
		first := changes.get(g, 0)
		var h = g
		while h + 1 < changes.length() and changes.get(h + 1, 0) - changes.get(h, 0) - 1 <= 2 * ctx:
			h += 1
		last := changes.get(h, 0)
		before := if first < ctx: first else: ctx
		after := if total - 1 - last < ctx: total - 1 - last else: ctx
		s := first - before
		e := last + after
		var la = 0
		var lb = 0
		for k in s..(e + 1):
			if kind.get(k, 0) != 2: la += 1
			if kind.get(k, 0) != 1: lb += 1
		sa := ai.get(s, 0) + (if la > 0: 1 else: 0)
		sb := bi.get(s, 0) + (if lb > 0: 1 else: 0)
		print("@@ -{rng(sa, la)} +{rng(sb, lb)} @@")
		for k in s..(e + 1):
			p := match_prefix(kind.get(k, 0))
			print("{p}{text.get(k, "")}")
		g = h + 1
	return ok(unit)

fn match_prefix(k: Int) String:
	if k == 0: return " "
	if k == 1: return "-"
	return "+"
