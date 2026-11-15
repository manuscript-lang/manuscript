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
	var t = List[Int](reserve: (n + 1) * w)
	for _k in 0..((n + 1) * w):
		t.append(0)
	var i = n - 1
	while i >= 0:
		var j = m - 1
		while j >= 0:
			if a.get(i, "") == b.get(j, ""):
				t[i * w + j] = t.get((i + 1) * w + j + 1, 0) + 1
			else:
				x := t.get((i + 1) * w + j, 0)
				y := t.get(i * w + j + 1, 0)
				t[i * w + j] = if x >= y: x else: y
			j -= 1
		i -= 1
	// ops: kind 0 same, 1 del, 2 ins
	var kind = List[Int]()
	var text = List[String]()
	var ab = List[Int]()
	var bb = List[Int]()
	var p = 0
	var q = 0
	while p < n or q < m:
		ab.append(p)
		bb.append(q)
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
	var out = List[String]()
	out.append("--- {name_a}")
	out.append("+++ {name_b}")
	var g = 0
	while g < changes.length():
		var h = g
		while h + 1 < changes.length() and changes.get(h + 1, 0) - changes.get(h, 0) - 1 <= 2 * ctx:
			h += 1
		first := changes.get(g, 0)
		last := changes.get(h, 0)
		s0 := if first - ctx > 0: first - ctx else: 0
		e0 := if last + ctx < total - 1: last + ctx else: total - 1
		var la = 0
		var lb = 0
		var body = List[String]()
		for k in s0..(e0 + 1):
			kk := kind.get(k, 0)
			tx := text.get(k, "")
			if kk == 0:
				la += 1
				lb += 1
				body.append(" {tx}")
			else if kk == 1:
				la += 1
				body.append("-{tx}")
			else:
				lb += 1
				body.append("+{tx}")
		sa := ab.get(s0, 0) + (if la > 0: 1 else: 0)
		sb := bb.get(s0, 0) + (if lb > 0: 1 else: 0)
		out.append("@@ -{rng(sa, la)} +{rng(sb, lb)} @@")
		for l in body:
			out.append(l.clone())
		g = h + 1
	print(out.join("\n"))
	return ok(unit)
