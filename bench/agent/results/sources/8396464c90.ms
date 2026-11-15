import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn num(s: String) Int?:
	n := s.length()
	if n < 1 or n > 6: return none
	for c in s.chars():
		if c < "0" or c > "9": return none
	return s.parse_int()

fn lcs(a: String, b: String) Int:
	x := a.chars()
	y := b.chars()
	var prev = List[Int]()
	for _j in 0..(y.length() + 1):
		prev.append(0)
	for i in 0..x.length():
		var cur = List[Int]()
		cur.append(0)
		for j in 0..y.length():
			if x.get(i, "") == y.get(j, ""):
				cur.append(prev.get(j, 0) + 1)
			else:
				p := prev.get(j + 1, 0)
				q := cur.get(j, 0)
				cur.append(if p > q: p else: q)
		prev = cur
	return prev.get(y.length(), 0)

fn edit(a: String, b: String) Int:
	x := a.chars()
	y := b.chars()
	var prev = List[Int]()
	for j in 0..(y.length() + 1):
		prev.append(j)
	for i in 0..x.length():
		var cur = List[Int]()
		cur.append(i + 1)
		for j in 0..y.length():
			cost := if x.get(i, "") == y.get(j, ""): 0 else: 1
			var best = prev.get(j, 0) + cost
			d := prev.get(j + 1, 0) + 1
			if d < best: best = d
			e := cur.get(j, 0) + 1
			if e < best: best = e
			cur.append(best)
		prev = cur
	return prev.get(y.length(), 0)

fn knap(cap: Int, ws: List[Int], vs: List[Int]) Int:
	var dp = List[Int]()
	for _c in 0..(cap + 1):
		dp.append(0)
	for i in 0..ws.length():
		w := ws.get(i, 0)
		v := vs.get(i, 0)
		var c = cap
		while c >= w:
			t := dp.get(c - w, 0) + v
			if t > dp.get(c, 0): dp[c] = t
			c -= 1
	return dp.get(cap, 0)

fn coins(amount: Int, cs: List[Int]) String:
	inf := 1000000000
	var dp = List[Int]()
	dp.append(0)
	for a in 1..(amount + 1):
		var best = inf
		for c in cs:
			if c <= a:
				t := dp.get(a - c, inf) + 1
				if t < best: best = t
		dp.append(best)
	r := dp.get(amount, inf)
	if r >= inf: return "impossible"
	return "{r}"

fn solve(line: String) String:
	bad := "error: bad command"
	t := line.split(" ")
	cmd := t.get(0, "")
	n := t.length()
	if cmd == "lcs" or cmd == "edit":
		if n != 3: return bad
		a := t.get(1, "")
		b := t.get(2, "")
		if a.length() == 0 or b.length() == 0: return bad
		if cmd == "lcs": return "{lcs(a, b)}"
		return "{edit(a, b)}"
	if cmd == "knap":
		if n < 2: return bad
		capo := num(t.get(1, ""))
		if capo.is_none(): return bad
		var ws = List[Int]()
		var vs = List[Int]()
		for i in 2..n:
			p := t.get(i, "").split(":")
			if p.length() != 2: return bad
			w := num(p.get(0, ""))
			v := num(p.get(1, ""))
			if w.is_none() or v.is_none(): return bad
			if w.get(0) < 1: return bad
			ws.append(w.get(0))
			vs.append(v.get(0))
		return "{knap(capo.get(0), ws, vs)}"
	if cmd == "coins":
		if n < 3: return bad
		amt := num(t.get(1, ""))
		if amt.is_none(): return bad
		var cs = List[Int]()
		for i in 2..n:
			c := num(t.get(i, ""))
			if c.is_none(): return bad
			if c.get(0) < 1: return bad
			cs.append(c.get(0))
		return coins(amt.get(0), cs)
	return bad

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim_chars(" \r").length() == 0: continue
		l := line.trim_end_chars("\r")
		print(solve(l))
