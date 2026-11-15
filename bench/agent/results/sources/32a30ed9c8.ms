import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Rec:
	path: String
	count: Int
	total: Int

fn digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	raw := read_all(stdin())?
	text := raw.decode_utf8().get("")
	var valid = 0
	var bad = 0
	var lv = Map[String, Int]()
	var st = [0, 0, 0, 0, 0]
	var lats = List[Int]()
	var best = -1
	var bestline = ""
	var paths = Map[String, Int]()
	var totals = Map[String, Int]()
	for line in text.split("\n"):
		if line.trim() == "": continue
		f := line.split(" ")
		ok := f.length() == 6 and f[0] != "" and f[3].starts_with("/") and f[4].length() == 3 and digits(f[4]) and digits(f[5]) and f[5].length() <= 9 and (f[1] == "DEBUG" or f[1] == "INFO" or f[1] == "WARN" or f[1] == "ERROR") and (f[2] == "GET" or f[2] == "POST" or f[2] == "PUT" or f[2] == "DELETE")
		if not ok:
			bad += 1
			continue
		valid += 1
		lat := f[5].parse_int().get(0)
		lv[f[1].clone()] = lv.get_or(f[1], 0) + 1
		d := f[4].parse_int().get(0) / 100
		idx := if d >= 2 and d <= 5: d - 2 else: 4
		st[idx] = st[idx] + 1
		lats.append(lat)
		if lat > best:
			best = lat
			bestline = "{lat} {f[2]} {f[3]} {f[0]}"
		paths[f[3].clone()] = paths.get_or(f[3], 0) + 1
		totals[f[3].clone()] = totals.get_or(f[3], 0) + lat
	print("valid: {valid}")
	print("malformed: {bad}")
	print("DEBUG: {lv.get_or("DEBUG", 0)}")
	print("INFO: {lv.get_or("INFO", 0)}")
	print("WARN: {lv.get_or("WARN", 0)}")
	print("ERROR: {lv.get_or("ERROR", 0)}")
	print("status: 2xx={st[0]} 3xx={st[1]} 4xx={st[2]} 5xx={st[3]} other={st[4]}")
	var p = 0
	if valid > 0:
		s := lats.sorted()
		p = s.get((95 * valid + 99) / 100 - 1, 0)
	print("p95: {p}")
	if valid > 0: print("slowest: {bestline}")
	print("top:")
	var recs = List[Rec]()
	for e in paths.entries():
		recs.append(Rec(e.key.clone(), e.value, totals.get_or(e.key, 0)))
	recs.sort(fn(a: Rec, b: Rec) Int: if a.count != b.count: b.count - a.count else: (if a.path < b.path: -1 else: (if a.path > b.path: 1 else: 0)))
	var i = 0
	while i < recs.length() and i < 3:
		r := recs[i]
		print("{r.path} {r.count} avg={r.total / r.count}")
		i += 1
