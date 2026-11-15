import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Agg:
	path: String
	count: Int
	total: Int

fn all_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if c < "0" or c > "9": return false
	return true

fn level_index(s: String) Int:
	if s == "DEBUG": return 0
	if s == "INFO": return 1
	if s == "WARN": return 2
	if s == "ERROR": return 3
	return -1

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Void!:
	data := read_all(stdin(), none)?
	input := data.decode_utf8().get("")
	var valid = 0
	var malformed = 0
	var levels = [0, 0, 0, 0]
	var st = [0, 0, 0, 0, 0]
	var lats = List[Int]()
	var best = -1
	var best_line = ""
	var counts = Map[String, Int]()
	var totals = Map[String, Int]()
	for line in input.split("\n", none):
		if line.trim() == "": continue
		f := line.split(" ", none)
		if f.length() != 6:
			malformed += 1
			continue
		li := level_index(f.get(1, ""))
		m := f.get(2, "")
		p := f.get(3, "")
		s := f.get(4, "")
		l := f.get(5, "")
		ok_m := m == "GET" or m == "POST" or m == "PUT" or m == "DELETE"
		if f.get(0, "").length() == 0 or li < 0 or not ok_m or not p.starts_with("/") or s.length() != 3 or not all_digits(s) or not all_digits(l) or l.length() > 9:
			malformed += 1
			continue
		lat := l.parse_int().get(0)
		valid += 1
		levels[li] = levels[li] + 1
		d := s.slice(0, 1).get("0")
		if d == "2": st[0] = st[0] + 1
		else if d == "3": st[1] = st[1] + 1
		else if d == "4": st[2] = st[2] + 1
		else if d == "5": st[3] = st[3] + 1
		else: st[4] = st[4] + 1
		lats.append(lat)
		if lat > best:
			best = lat
			best_line = "{lat} {m} {p} {f.get(0, "")}"
		counts[p.clone()] = counts.get_or(p, 0) + 1
		totals[p.clone()] = totals.get_or(p, 0) + lat
	print("valid: {valid}")
	print("malformed: {malformed}")
	print("DEBUG: {levels[0]}")
	print("INFO: {levels[1]}")
	print("WARN: {levels[2]}")
	print("ERROR: {levels[3]}")
	print("status: 2xx={st[0]} 3xx={st[1]} 4xx={st[2]} 5xx={st[3]} other={st[4]}")
	n := lats.length()
	lats.sort()
	if n == 0:
		print("p95: 0")
	else:
		print("p95: {lats.get((95 * n + 99) / 100 - 1, 0)}")
		print("slowest: {best_line}")
	print("top:")
	var aggs = List[Agg]()
	for e in counts.entries():
		aggs.append(Agg(path: e.key.clone(), count: e.value, total: totals.get_or(e.key, 0)))
	aggs.sort(fn a, b: if a.count != b.count: b.count.compare(a.count) else: a.path.compare(b.path))
	var i = 0
	while i < aggs.length() and i < 3:
		a := aggs.get(i, Agg(path: "", count: 1, total: 0))
		print("{a.path} {a.count} avg={a.total / a.count}")
		i += 1
