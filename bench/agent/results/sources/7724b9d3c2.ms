import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Rec:
	ts: String
	method: String
	path: String
	lat: Int

type PathStat:
	path: String
	count: Int
	total: Int

fn all_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var valid = 0
	var malformed = 0
	var levels = Map[String, Int]()
	var st = [0, 0, 0, 0, 0]
	var lats = List[Int]()
	var counts = Map[String, Int]()
	var totals = Map[String, Int]()
	var slow_lat = -1
	var slow = ""
	for line in text.split("\n"):
		if line.trim().length() == 0: continue
		f := line.split(" ")
		if f.length() != 6:
			malformed += 1
			continue
		level := f.get(1, "")
		method := f.get(2, "")
		path := f.get(3, "")
		status := f.get(4, "")
		latS := f.get(5, "")
		ok := f.get(0, "").length() > 0 and ["DEBUG", "INFO", "WARN", "ERROR"].contains(level) and ["GET", "POST", "PUT", "DELETE"].contains(method) and path.starts_with("/") and status.length() == 3 and all_digits(status) and all_digits(latS) and latS.length() <= 9
		if not ok:
			malformed += 1
			continue
		valid += 1
		levels[level.clone()] = levels.get_or(level, 0) + 1
		d := status.slice(0, 1).get("0")
		idx := if d == "2": 0 else if d == "3": 1 else if d == "4": 2 else if d == "5": 3 else: 4
		st[idx] = st.get(idx, 0) + 1
		lat := latS.parse_int().get(0)
		lats.append(lat)
		if lat > slow_lat:
			slow_lat = lat
			slow = "{lat} {method} {path} {f.get(0, "")}"
		counts[path.clone()] = counts.get_or(path, 0) + 1
		totals[path.clone()] = totals.get_or(path, 0) + lat
	print("valid: {valid}")
	print("malformed: {malformed}")
	for l in ["DEBUG", "INFO", "WARN", "ERROR"]:
		print("{l}: {levels.get_or(l, 0)}")
	print("status: 2xx={st.get(0, 0)} 3xx={st.get(1, 0)} 4xx={st.get(2, 0)} 5xx={st.get(3, 0)} other={st.get(4, 0)}")
	lats.sort()
	n := lats.length()
	rank := (95 * n + 99) / 100
	print("p95: {if n == 0: 0 else: lats.get(rank - 1, 0)}")
	if n > 0: print("slowest: {slow}")
	print("top:")
	var arr = List[PathStat]()
	for e in counts.entries():
		arr.append(PathStat(e.key.clone(), e.value, totals.get_or(e.key, 0)))
	arr.sort(fn a, b: if a.count != b.count: b.count - a.count else: (if a.path < b.path: -1 else: (if a.path > b.path: 1 else: 0)))
	for i in 0..(if arr.length() < 3: arr.length() else: 3):
		p := arr.get(i, PathStat("", 0, 0))
		print("{p.path} {p.count} avg={p.total / p.count}")
