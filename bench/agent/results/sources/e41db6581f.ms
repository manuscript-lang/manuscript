import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn rng(s: Int, l: Int) String:
	var a = s
	if l > 0: a = s + 1
	if l == 1: return "{a}"
	return "{a},{l}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var all = List[String]()
	for line in lines(stdin()):
		all.append(line)
	header := all.get(0, "").split(" ")
	name_a := header.get(0, "")
	name_b := header.get(1, "")
	ctx := header.get(2, "0").parse_int().ok_or(Error("bad"))?
	n := header.get(3, "0").parse_int().ok_or(Error("bad"))?
	m := header.get(4, "0").parse_int().ok_or(Error("bad"))?
	var a = List[String]()
	var b = List[String]()
	for i in 0..n:
		a.append(all.get(1 + i, ""))
	for j in 0..m:
		b.append(all.get(1 + n + i_off(n, j), ""))
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
				x := t.get((i + 1) * w + j, 0)
				y := t.get(i * w + j + 1, 0)
				t[i * w + j] = if x >= y: x else: y
			j -= 1
		i -= 1
	// script
	var kinds = List[String]()
	var texts = List[String]()
	var p = 0
	var q = 0
	while p < n or q < m:
		if p < n and q < m and a.get(p, "") == b.get(q, ""):
			kinds.append(" ")
			texts.append(a.get(p, ""))
			p += 1
			q += 1
		else if q == m or (p < n and t.get((p + 1) * w + q, 0) >= t.get(p * w + q + 1, 0)):
			kinds.append("-")
			texts.append(a.get(p, ""))
			p += 1
		else:
			kinds.append("+")
			texts.append(b.get(q, ""))
			q += 1
	total := kinds.length()
	var changes = List[Int]()
	for k in 0..total:
		if kinds.get(k, " ") != " ": changes.append(k)
	if changes.length() == 0: return ok(unit)
	// prefix counts
	var pa = List[Int]()
	var pb = List[Int]()
	pa.append(0)
	pb.append(0)
	for k in 0..total:
		kk := kinds.get(k, " ")
		pa.append(pa.get(k, 0) + (if kk != "+": 1 else: 0))
		pb.append(pb.get(k, 0) + (if kk != "-": 1 else: 0))
	var out = List[String]()
	out.append("--- {name_a}")
	out.append("+++ {name_b}")
	var gi = 0
	while gi < changes.length():
		f := changes.get(gi, 0)
		var l = f
		var gj = gi
		while gj + 1 < changes.length() and changes.get(gj + 1, 0) - changes.get(gj, 0) - 1 <= 2 * ctx:
			gj += 1
			l = changes.get(gj, 0)
		s := if f - ctx > 0: f - ctx else: 0
		e := if l + ctx + 1 < total: l + ctx + 1 else: total
		la := pa.get(e, 0) - pa.get(s, 0)
		lb := pb.get(e, 0) - pb.get(s, 0)
		out.append("@@ -{rng(pa.get(s, 0), la)} +{rng(pb.get(s, 0), lb)} @@")
		for k in s..e:
			out.append("{kinds.get(k, " ")}{texts.get(k, "")}")
		gi = gj + 1
	for line in out:
		print(line)

fn i_off(n: Int, j: Int) Int: j
