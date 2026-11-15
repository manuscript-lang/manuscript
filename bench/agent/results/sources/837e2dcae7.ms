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
		all.append(line)
	if all.length() == 0: return ok(unit)
	head := all.get(0, "").split(" ")
	name_a := head.get(0, "")
	name_b := head.get(1, "")
	ctx := head.get(2, "0").parse_int().get(0)
	n := head.get(3, "0").parse_int().get(0)
	m := head.get(4, "0").parse_int().get(0)
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
				t[i * w + j] = t.get(i * w + j + w + 1, 0) + 1
			else:
				x := t.get(i * w + j + w, 0)
				y := t.get(i * w + j + 1, 0)
				t[i * w + j] = if x >= y: x else: y
			j -= 1
		i -= 1
	// script
	var kind = List[Int]()
	var text = List[String]()
	var ca = List[Int]()
	var cb = List[Int]()
	var p = 0
	var q = 0
	while p < n or q < m:
		ca.append(p)
		cb.append(q)
		if p < n and q < m and a.get(p, "") == b.get(q, ""):
			kind.append(0)
			text.append(a.get(p, ""))
			p += 1
			q += 1
		else if q == m or (p < n and t.get((p + 1) * w + q, 0) >= t.get(p * w + q + 1, 0)):
			kind.append(1)
			text.append(a.get(p, ""))
			p += 1
		else:
			kind.append(2)
			text.append(b.get(q, ""))
			q += 1
	total := kind.length()
	var changes = List[Int]()
	for k in 0..total:
		if kind.get(k, 0) != 0: changes.append(k)
	if changes.length() == 0: return ok(unit)
	print("--- {name_a}")
	print("+++ {name_b}")
	var gi = 0
	while gi < changes.length():
		first := changes.get(gi, 0)
		var gj = gi
		while gj + 1 < changes.length() and changes.get(gj + 1, 0) - changes.get(gj, 0) - 1 <= 2 * ctx:
			gj += 1
		last := changes.get(gj, 0)
		bef := if first < ctx: first else: ctx
		aft0 := total - 1 - last
		aft := if aft0 < ctx: aft0 else: ctx
		s := first - bef
		e := last + aft
		var la = 0
		var lb = 0
		for k in s..(e + 1):
			if kind.get(k, 0) != 2: la += 1
			if kind.get(k, 0) != 1: lb += 1
		sa := ca.get(s, 0) + (if la > 0: 1 else: 0)
		sb := cb.get(s, 0) + (if lb > 0: 1 else: 0)
		print("@@ -{rng(sa, la)} +{rng(sb, lb)} @@")
		for k in s..(e + 1):
			kd := kind.get(k, 0)
			pre := if kd == 0: " " else if kd == 1: "-" else: "+"
			print("{pre}{text.get(k, "")}")
		gi = gj + 1
