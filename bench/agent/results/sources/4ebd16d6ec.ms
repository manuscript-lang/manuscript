import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Stat:
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
	var valid = 0
	var bad = 0
	var lv = Map[String, Int]()
	var st = [0, 0, 0, 0, 0]
	var lats = List[Int]()
	var best = -1
	var bestline = ""
	var stats = Map[String, Stat]()
	for line in lines(stdin()):
		if line.trim() == "": continue
		f := line.split(" ")
		ok := f.length() == 6 and f.get(0, "") != "" and (f.get(1, "") == "DEBUG" or f.get(1, "") == "INFO" or f.get(1, "") == "WARN" or f.get(1, "") == "ERROR") and (f.get(2, "") == "GET" or f.get(2, "") == "POST" or f.get(2, "") == "PUT" or f.get(2, "") == "DELETE") and f.get(3, "").starts_with("/") and f.get(4, "").length() == 3 and digits(f.get(4, "")) and digits(f.get(5, "")) and f.get(5, "").length() <= 9
		if not ok:
			bad += 1
			continue
		valid += 1
		lv[f.get(1, "")] = lv.get_or(f.get(1, ""), 0) + 1
		d := f.get(4, "").slice(0, 1)?
		idx := if d == "2": 0 else if d == "3": 1 else if d == "4": 2 else if d == "5": 3 else: 4
		st[idx] = st.get(idx, 0) + 1
		lat := f.get(5, "").parse_int().get(0)
		lats.append(lat)
		if lat > best:
			best = lat
			bestline = "{lat} {f.get(2, "")} {f.get(3, "")} {f.get(0, "")}"
		p := f.get(3, "")
		if var s = stats[p]?:
			s.count += 1
			s.total += lat
		else:
			stats[p.clone()] = Stat(p.clone(), 1, lat)
	print("valid: {valid}")
	print("malformed: {bad}")
	print("DEBUG: {lv.get_or("DEBUG", 0)}")
	print("INFO: {lv.get_or("INFO", 0)}")
	print("WARN: {lv.get_or("WARN", 0)}")
	print("ERROR: {lv.get_or("ERROR", 0)}")
	print("status: 2xx={st.get(0, 0)} 3xx={st.get(1, 0)} 4xx={st.get(2, 0)} 5xx={st.get(3, 0)} other={st.get(4, 0)}")
	lats.sort()
	rank := (95 * valid + 99) / 100
	print("p95: {if valid == 0: 0 else: lats.get(rank - 1, 0)}")
	if valid > 0:
		print("slowest: {bestline}")
	print("top:")
	var all = List[Stat]()
	for e in stats.entries():
		all.append(Stat(e.value.path.clone(), e.value.count, e.value.total))
	all.sort(fn(a: Stat, b: Stat) Int: if a.count != b.count: b.count - a.count else: (if a.path < b.path: -1 else: (if a.path > b.path: 1 else: 0)))
	var i = 0
	for s in all:
		if i >= 3: break
		print("{s.path} {s.count} avg={s.total / s.count}")
		i += 1
