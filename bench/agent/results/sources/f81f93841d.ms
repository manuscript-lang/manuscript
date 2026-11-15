import Bytes from "@std/bytes.ms"
import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn num(s: String) Int?:
	n := s.length()
	if n < 1 or n > 6: return none
	for c in s.chars():
		if not "0123456789".contains(c): return none
	return s.parse_int()

fn lcs(a: Bytes, b: Bytes) Int:
	m := b.length()
	var prev = List[Int]()
	var cur = List[Int]()
	for _j in 0..m + 1:
		prev.append(0)
		cur.append(0)
	for i in 0..a.length():
		for j in 0..m:
			if a.get(i) == b.get(j):
				cur[j + 1] = prev[j] + 1
			else:
				x := prev[j + 1]
				y := cur[j]
				cur[j + 1] = if x > y: x else: y
		for j in 0..m + 1:
			prev[j] = cur[j]
	return prev[m]

fn edit(a: Bytes, b: Bytes) Int:
	m := b.length()
	var prev = List[Int]()
	var cur = List[Int]()
	for j in 0..m + 1:
		prev.append(j)
		cur.append(0)
	for i in 0..a.length():
		cur[0] = i + 1
		for j in 0..m:
			cost := if a.get(i) == b.get(j): 0 else: 1
			var best = prev[j] + cost
			if prev[j + 1] + 1 < best: best = prev[j + 1] + 1
			if cur[j] + 1 < best: best = cur[j] + 1
			cur[j + 1] = best
		for j in 0..m + 1:
			prev[j] = cur[j]
	return prev[m]

fn knap(toks: List[String]) String:
	if toks.length() < 2: return "error: bad command"
	cap := num(toks[1]).get(-1)
	if cap < 0: return "error: bad command"
	var ws = List[Int]()
	var vs = List[Int]()
	for i in 2..toks.length():
		parts := toks[i].split(":")
		if parts.length() != 2: return "error: bad command"
		w := num(parts[0]).get(-1)
		v := num(parts[1]).get(-1)
		if w < 1 or v < 0: return "error: bad command"
		ws.append(w)
		vs.append(v)
	var dp = List[Int]()
	for _c in 0..cap + 1:
		dp.append(0)
	for i in 0..ws.length():
		w := ws[i]
		v := vs[i]
		var c = cap
		while c >= w:
			t := dp[c - w] + v
			if t > dp[c]: dp[c] = t
			c -= 1
	return "{dp[cap]}"

fn coins(toks: List[String]) String:
	if toks.length() < 3: return "error: bad command"
	amt := num(toks[1]).get(-1)
	if amt < 0: return "error: bad command"
	var cs = List[Int]()
	for i in 2..toks.length():
		c := num(toks[i]).get(-1)
		if c < 1: return "error: bad command"
		cs.append(c)
	inf := amt + 1
	var dp = List[Int]()
	for _a in 0..amt + 1:
		dp.append(inf)
	dp[0] = 0
	for a in 1..amt + 1:
		for c in cs:
			if c <= a and dp[a - c] + 1 < dp[a]:
				dp[a] = dp[a - c] + 1
	if dp[amt] >= inf: return "impossible"
	return "{dp[amt]}"

fn handle(line: String) String:
	toks := line.split(" ")
	cmd := toks[0]
	if cmd == "lcs" or cmd == "edit":
		if toks.length() != 3 or toks[1].is_empty() or toks[2].is_empty(): return "error: bad command"
		a := toks[1].as_bytes()
		b := toks[2].as_bytes()
		if cmd == "lcs": return "{lcs(a, b)}"
		return "{edit(a, b)}"
	if cmd == "knap": return knap(toks)
	if cmd == "coins": return coins(toks)
	return "error: bad command"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		l := if line.ends_with("\r"): line.slice(0, line.length() - 1)? else: line
		if l.fields().length() == 0: continue
		print(handle(l))
