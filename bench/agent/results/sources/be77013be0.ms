import lines from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

fn rng(s: Int, l: Int) String:
	if l == 1: return "{s}"
	return "{s},{l}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var all = List[String]()
	for line in lines(stdin()):
		all.append(line)
	parts := all.get(0, "").split(" ")
	na := parts.get(0, "")
	nb := parts.get(1, "")
	ctx := parts.get(2, "0").parse_int().get(0)
	n := parts.get(3, "0").parse_int().get(0)
	m := parts.get(4, "0").parse_int().get(0)
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
	var i = n
	while i >= 0:
		var j = m
		while j >= 0:
			if i < n and j < m:
				if a.get(i, "") == b.get(j, ""):
					t[i * w + j] = t.get((i + 1) * w + j + 1, 0) + 1
				else:
					x := t.get((i + 1) * w + j, 0)
					y := t.get(i * w + j + 1, 0)
					t[i * w + j] = if x >= y: x else: y
			j -= 1
		i -= 1
	var kind = List[Int]()
	var text = List[String]()
	var pa = List[Int]()
	var pb = List[Int]()
	var ci = 0
	var cj = 0
	while ci < n or cj < m:
		pa.append(ci)
		pb.append(cj)
		if ci < n and cj < m and a.get(ci, "") == b.get(cj, ""):
			kind.append(0)
			text.append(a.get(ci, ""))
			ci += 1
			cj += 1
		else if cj == m or (ci < n and t.get((ci + 1) * w + cj, 0) >= t.get(ci * w + cj + 1, 0)):
			kind.append(1)
			text.append(a.get(ci, ""))
			ci += 1
		else:
			kind.append(2)
			text.append(b.get(cj, ""))
			cj += 1
	pa.append(ci)
	pb.append(cj)
	total := kind.length()
	var changes = List[Int]()
	for k in 0..total:
		if kind.get(k, 0) != 0: changes.append(k)
	if changes.length() == 0: return ok(unit)
	print("--- {na}")
	print("+++ {nb}")
	var g = 0
	while g < changes.length():
		var h = g
		while h + 1 < changes.length() and changes.get(h + 1, 0) - changes.get(h, 0) - 1 <= 2 * ctx:
			h += 1
		first := changes.get(g, 0)
		last := changes.get(h, 0)
		s0 := if first - ctx < 0: 0 else: first - ctx
		e0 := if last + ctx > total - 1: total - 1 else: last + ctx
		var la = 0
		var lb = 0
		for k in s0..(e0 + 1):
			if kind.get(k, 0) != 2: la += 1
			if kind.get(k, 0) != 1: lb += 1
		sa := pa.get(s0, 0) + (if la > 0: 1 else: 0)
		sb := pb.get(s0, 0) + (if lb > 0: 1 else: 0)
		print("@@ -{rng(sa, la)} +{rng(sb, lb)} @@")
		for k in s0..(e0 + 1):
			kk := kind.get(k, 0)
			p := if kk == 0: " " else if kk == 1: "-" else: "+"
			print("{p}{text.get(k, "")}")
		g = h + 1
