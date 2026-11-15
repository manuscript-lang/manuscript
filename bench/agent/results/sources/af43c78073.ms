import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"
import max, min from "@std/math/math.ms"

fn num(s: String) Int:
	n := s.length()
	if n < 1 or n > 6: return -1
	var v = 0
	for i in 0..n:
		c := s.scalar_at(i)
		if c < 48 or c > 57: return -1
		v = v * 10 + (c - 48)
	return v

fn lcs(a: String, b: String) Int:
	m := b.length()
	var prev = List[Int]()
	for _j in 0..m + 1: prev.append(0)
	for i in 0..a.length():
		var cur = List[Int]()
		cur.append(0)
		for j in 0..m:
			if a.scalar_at(i) == b.scalar_at(j):
				cur.append(prev.get(j, 0) + 1)
			else:
				cur.append(max(prev.get(j + 1, 0), cur.get(j, 0)))
		prev = cur
	return prev.get(m, 0)

fn edit(a: String, b: String) Int:
	m := b.length()
	var prev = List[Int]()
	for j in 0..m + 1: prev.append(j)
	for i in 0..a.length():
		var cur = List[Int]()
		cur.append(i + 1)
		for j in 0..m:
			cost := if a.scalar_at(i) == b.scalar_at(j): 0 else: 1
			best := min(prev.get(j, 0) + cost, min(prev.get(j + 1, 0) + 1, cur.get(j, 0) + 1))
			cur.append(best)
		prev = cur
	return prev.get(m, 0)

fn solve(line: String) String:
	t := line.split(" ")
	cmd := t.get(0, "")
	n := t.length()
	if cmd == "lcs" or cmd == "edit":
		if n != 3: return "error: bad command"
		a := t.get(1, "")
		b := t.get(2, "")
		if a.length() == 0 or b.length() == 0: return "error: bad command"
		if cmd == "lcs": return "{lcs(a, b)}"
		return "{edit(a, b)}"
	if cmd == "knap":
		if n < 2: return "error: bad command"
		cap := num(t.get(1, ""))
		if cap < 0: return "error: bad command"
		var dp = List[Int]()
		for _i in 0..cap + 1: dp.append(0)
		for k in 2..n:
			p := t.get(k, "").split(":")
			if p.length() != 2: return "error: bad command"
			w := num(p.get(0, ""))
			v := num(p.get(1, ""))
			if w < 1 or v < 0: return "error: bad command"
			var c = cap
			while c >= w:
				cand := dp.get(c - w, 0) + v
				if cand > dp.get(c, 0): dp[c] = cand
				c -= 1
		return "{dp.get(cap, 0)}"
	if cmd == "coins":
		if n < 3: return "error: bad command"
		amt := num(t.get(1, ""))
		if amt < 0: return "error: bad command"
		var coins = List[Int]()
		for k in 2..n:
			c := num(t.get(k, ""))
			if c < 1: return "error: bad command"
			coins.append(c)
		inf := amt + 1
		var dp = List[Int]()
		dp.append(0)
		for a in 1..amt + 1:
			var best = inf
			for c in coins:
				if c <= a:
					cand := dp.get(a - c, inf) + 1
					if cand < best: best = cand
			dp.append(best)
		r := dp.get(amt, inf)
		if r >= inf: return "impossible"
		return "{r}"
	return "error: bad command"

fn blank(s: String) Bool:
	for i in 0..s.length():
		if s.scalar_at(i) != 32: return false
	return true

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if blank(line): continue
		print(solve(line))
