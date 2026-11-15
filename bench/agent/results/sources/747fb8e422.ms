import max, min from "@std/math/math.ms"
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
	for _j in 0..y.length() + 1:
		prev.append(0)
	for i in 0..x.length():
		var cur = List[Int]()
		cur.append(0)
		for j in 0..y.length():
			if x.get(i, "") == y.get(j, ""):
				cur.append(prev.get(j, 0) + 1)
			else:
				cur.append(max(prev.get(j + 1, 0), cur.get(j, 0)))
		prev = cur
	return prev.get(y.length(), 0)

fn edit(a: String, b: String) Int:
	x := a.chars()
	y := b.chars()
	var prev = List[Int]()
	for j in 0..y.length() + 1:
		prev.append(j)
	for i in 0..x.length():
		var cur = List[Int]()
		cur.append(i + 1)
		for j in 0..y.length():
			cost := if x.get(i, "") == y.get(j, ""): 0 else: 1
			cur.append(min(min(prev.get(j + 1, 0) + 1, cur.get(j, 0) + 1), prev.get(j, 0) + cost))
		prev = cur
	return prev.get(y.length(), 0)

fn solve(line: String) String:
	bad := "error: bad command"
	t := line.split(" ")
	cmd := t.get(0, "")
	if cmd == "lcs" or cmd == "edit":
		if t.length() != 3: return bad
		if cmd == "lcs": return "{lcs(t.get(1, ""), t.get(2, ""))}"
		return "{edit(t.get(1, ""), t.get(2, ""))}"
	if cmd == "knap":
		if t.length() < 2: return bad
		cap := num(t.get(1, "")).get(-1)
		if cap < 0: return bad
		var dp = List[Int]()
		for _i in 0..cap + 1:
			dp.append(0)
		for k in 2..t.length():
			p := t.get(k, "").split(":")
			if p.length() != 2: return bad
			w := num(p.get(0, "")).get(-1)
			v := num(p.get(1, "")).get(-1)
			if w < 1 or v < 0: return bad
			var c = cap
			while c >= w:
				cand := dp.get(c - w, 0) + v
				if cand > dp.get(c, 0): dp[c] = cand
				c -= 1
		return "{dp.get(cap, 0)}"
	if cmd == "coins":
		if t.length() < 3: return bad
		amt := num(t.get(1, "")).get(-1)
		if amt < 0: return bad
		var cs = List[Int]()
		for k in 2..t.length():
			c := num(t.get(k, "")).get(-1)
			if c < 1: return bad
			cs.append(c)
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
	return bad

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		print(solve(line))
