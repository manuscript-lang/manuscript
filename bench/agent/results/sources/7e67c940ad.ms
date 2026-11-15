import stdin from "@std/io/io.ms"
import max, min from "@std/math/math.ms"
import lines from "@std/io/streams.ms"

fn codes(s: String) List[Int]:
	var out = List[Int]()
	bs := s.as_bytes()
	for i in 0..bs.length():
		out.append(bs.get(i, 0).to_int())
	return out

fn num(s: String) Int?:
	n := s.length()
	if n < 1 or n > 6: return none
	for c in codes(s):
		if c < 48 or c > 57: return none
	return s.parse_int()

fn lcs(a: String, b: String) Int:
	x := codes(a)
	y := codes(b)
	var prev = List[Int]()
	for _j in 0..y.length() + 1:
		prev.append(0)
	for i in 0..x.length():
		var cur = List[Int]()
		cur.append(0)
		for j in 0..y.length():
			if x.get(i, 0) == y.get(j, 1):
				cur.append(prev.get(j, 0) + 1)
			else:
				cur.append(max(prev.get(j + 1, 0), cur.get(j, 0)))
		prev = cur
	return prev.get(y.length(), 0)

fn edit(a: String, b: String) Int:
	x := codes(a)
	y := codes(b)
	var prev = List[Int]()
	for j in 0..y.length() + 1:
		prev.append(j)
	for i in 0..x.length():
		var cur = List[Int]()
		cur.append(i + 1)
		for j in 0..y.length():
			cost := if x.get(i, 0) == y.get(j, 1): 0 else: 1
			best := min(prev.get(j, 0) + cost, min(prev.get(j + 1, 0) + 1, cur.get(j, 0) + 1))
			cur.append(best)
		prev = cur
	return prev.get(y.length(), 0)

fn knap(parts: List[String]) String:
	if parts.length() < 2: return "error: bad command"
	capo := num(parts.get(1, ""))
	if capo.is_none(): return "error: bad command"
	cap := capo.get(0)
	var ws = List[Int]()
	var vs = List[Int]()
	for i in 2..parts.length():
		kv := parts.get(i, "").split(":")
		if kv.length() != 2: return "error: bad command"
		w := num(kv.get(0, ""))
		v := num(kv.get(1, ""))
		if w.is_none() or v.is_none(): return "error: bad command"
		if w.get(0) < 1: return "error: bad command"
		ws.append(w.get(0))
		vs.append(v.get(0))
	var dp = List[Int]()
	for _c in 0..cap + 1:
		dp.append(0)
	for i in 0..ws.length():
		w := ws.get(i, 0)
		v := vs.get(i, 0)
		var c = cap
		while c >= w:
			cand := dp.get(c - w, 0) + v
			if cand > dp.get(c, 0): dp[c] = cand
			c -= 1
	return "{dp.get(cap, 0)}"

fn coins(parts: List[String]) String:
	if parts.length() < 3: return "error: bad command"
	ao := num(parts.get(1, ""))
	if ao.is_none(): return "error: bad command"
	amt := ao.get(0)
	var cs = List[Int]()
	for i in 2..parts.length():
		c := num(parts.get(i, ""))
		if c.is_none(): return "error: bad command"
		if c.get(0) < 1: return "error: bad command"
		cs.append(c.get(0))
	inf := 1000000000
	var dp = List[Int]()
	dp.append(0)
	for a in 1..amt + 1:
		var best = inf
		for c in cs:
			if c <= a:
				d := dp.get(a - c, inf) + 1
				if d < best: best = d
		dp.append(best)
	r := dp.get(amt, inf)
	if r >= inf: return "impossible"
	return "{r}"

fn run(line: String) String:
	parts := line.split(" ")
	cmd := parts.get(0, "")
	if cmd == "lcs":
		if parts.length() != 3: return "error: bad command"
		if parts.get(1, "") == "" or parts.get(2, "") == "": return "error: bad command"
		return "{lcs(parts.get(1, ""), parts.get(2, ""))}"
	if cmd == "edit":
		if parts.length() != 3: return "error: bad command"
		if parts.get(1, "") == "" or parts.get(2, "") == "": return "error: bad command"
		return "{edit(parts.get(1, ""), parts.get(2, ""))}"
	if cmd == "knap": return knap(parts)
	if cmd == "coins": return coins(parts)
	return "error: bad command"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		l := if line.ends_with("\r"): line.slice(0, line.length() - 1)? else: line
		if l.trim() == "": continue
		print(run(l))
