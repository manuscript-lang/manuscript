import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Rec:
	path: String
	latency: Int
	method: String
	ts: String

fn all_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if c < "0" or c > "9": return false
	return true

fn in_list(s: String, xs: List[String]) Bool:
	for x in xs:
		if x == s: return true
	return false

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	levels := ["DEBUG", "INFO", "WARN", "ERROR"]
	methods := ["GET", "POST", "PUT", "DELETE"]
	var lc = [0, 0, 0, 0]
	var st = [0, 0, 0, 0, 0]
	var valid = 0
	var bad = 0
	var lats = List[Int]()
	var best = Rec("", -1, "", "")
	var sums = Map[String, Int]()
	var cnts = Map[String, Int]()
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		f := line.split(" ")
		ok := f.length() == 6 and f.get(0, "").length() > 0 and in_list(f.get(1, ""), levels) and in_list(f.get(2, ""), methods) and f.get(3, "").starts_with("/") and f.get(4, "").length() == 3 and all_digits(f.get(4, "")) and f.get(5, "").length() <= 9 and all_digits(f.get(5, ""))
		if not ok:
			bad += 1
			continue
		valid += 1
		for i in 0..4:
			if levels.get(i, "") == f.get(1, ""): lc[i] += 1
		first := f.get(4, "").chars().get(0, "0")
		if first == "2": st[0] += 1
		else if first == "3": st[1] += 1
		else if first == "4": st[2] += 1
		else if first == "5": st[3] += 1
		else: st[4] += 1
		lat := f.get(5, "").parse_int().get(0)
		lats.append(lat)
		if lat > best.latency:
			best = Rec(f.get(3, "").clone(), lat, f.get(2, "").clone(), f.get(0, "").clone())
		p := f.get(3, "").clone()
		sums[p.clone()] = sums.get_or(p, 0) + lat
		cnts[p.clone()] = cnts.get_or(p, 0) + 1
	print("valid: {valid}")
	print("malformed: {bad}")
	for i in 0..4:
		print("{levels.get(i, "")}: {lc.get(i, 0)}")
	print("status: 2xx={st.get(0, 0)} 3xx={st.get(1, 0)} 4xx={st.get(2, 0)} 5xx={st.get(3, 0)} other={st.get(4, 0)}")
	n := lats.length()
	if n == 0:
		print("p95: 0")
	else:
		s := lats.sorted()
		print("p95: {s.get((95 * n + 99) / 100 - 1, 0)}")
		print("slowest: {best.latency} {best.method} {best.path} {best.ts}")
	print("top:")
	var ents = List[Rec]()
	for e in cnts.entries():
		ents.append(Rec(e.key.clone(), e.value, "", ""))
	ents.sort(fn(a: Rec, b: Rec) Int: if a.latency != b.latency: b.latency - a.latency else: if a.path < b.path: -1 else: if a.path > b.path: 1 else: 0)
	for i in 0..(if ents.length() < 3: ents.length() else: 3):
		p := ents[i].path
		print("{p} {ents[i].latency} avg={sums.get_or(p, 0) / ents[i].latency}")
