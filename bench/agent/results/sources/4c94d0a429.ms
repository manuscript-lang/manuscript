import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn is_num(s: String) Bool:
	n := s.length()
	if n < 1 or n > 6: return false
	for c in s.scalar_values():
		if c < 48 or c > 57: return false
	return true

fn num(s: String) Int: s.parse_int().get(0)

fn lcs(a: List[Int], b: List[Int]) Int:
	var prev = List[Int]()
	for _j in 0..b.length() + 1: prev.append(0)
	for i in 0..a.length():
		var cur = List[Int]()
		cur.append(0)
		for j in 0..b.length():
			if a.get(i, 0) == b.get(j, 0):
				cur.append(prev.get(j, 0) + 1)
			else:
				cur.append(prev.get(j + 1, 0).max(cur.get(j, 0)))
		prev = cur
	return prev.get(b.length(), 0)

fn edit(a: List[Int], b: List[Int]) Int:
	var prev = List[Int]()
	for j in 0..b.length() + 1: prev.append(j)
	for i in 0..a.length():
		var cur = List[Int]()
		cur.append(i + 1)
		for j in 0..b.length():
			cost := if a.get(i, 0) == b.get(j, 0): 0 else: 1
			best := (prev.get(j, 0) + cost).min(prev.get(j + 1, 0) + 1).min(cur.get(j, 0) + 1)
			cur.append(best)
		prev = cur
	return prev.get(b.length(), 0)

fn knap(cap: Int, ws: List[Int], vs: List[Int]) Int:
	var dp = List[Int]()
	for _i in 0..cap + 1: dp.append(0)
	for i in 0..ws.length():
		w := ws.get(i, 0)
		v := vs.get(i, 0)
		var c = cap
		while c >= w:
			cand := dp.get(c - w, 0) + v
			if cand > dp.get(c, 0): dp[c] = cand
			c -= 1
	return dp.get(cap, 0)

fn coins(amount: Int, cs: List[Int]) String:
	inf := 1000000000
	var dp = List[Int]()
	dp.append(0)
	for a in 1..amount + 1:
		var best = inf
		for c in cs:
			if c <= a:
				x := dp.get(a - c, inf) + 1
				if x < best: best = x
		dp.append(best)
	r := dp.get(amount, inf)
	if r >= inf: return "impossible"
	return "{r}"

fn run(line: String) String:
	t := line.split(" ")
	bad := "error: bad command"
	cmd := t.get(0, "")
	n := t.length()
	if cmd == "lcs" or cmd == "edit":
		if n != 3: return bad
		a := t.get(1, "")
		b := t.get(2, "")
		if a.is_empty() or b.is_empty(): return bad
		if cmd == "lcs": return "{lcs(a.scalar_values(), b.scalar_values())}"
		return "{edit(a.scalar_values(), b.scalar_values())}"
	if cmd == "knap":
		if n < 2: return bad
		if not is_num(t.get(1, "")): return bad
		var ws = List[Int]()
		var vs = List[Int]()
		for i in 2..n:
			p := t.get(i, "").split(":")
			if p.length() != 2: return bad
			if not is_num(p.get(0, "")) or not is_num(p.get(1, "")): return bad
			w := num(p.get(0, ""))
			if w < 1: return bad
			ws.append(w)
			vs.append(num(p.get(1, "")))
		return "{knap(num(t.get(1, "")), ws, vs)}"
	if cmd == "coins":
		if n < 3: return bad
		if not is_num(t.get(1, "")): return bad
		var cs = List[Int]()
		for i in 2..n:
			s := t.get(i, "")
			if not is_num(s): return bad
			c := num(s)
			if c < 1: return bad
			cs.append(c)
		return coins(num(t.get(1, "")), cs)
	return bad

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim().is_empty(): continue
		print(run(line))
