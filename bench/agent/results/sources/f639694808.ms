import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn all_digits(s: String) Bool:
	for c in s.chars():
		if c < "0" or c > "9": return false
	return true

fn is_level(s: String) Bool: s == "DEBUG" or s == "INFO" or s == "WARN" or s == "ERROR"

fn is_method(s: String) Bool: s == "GET" or s == "POST" or s == "PUT" or s == "DELETE"

type Row:
	path: String
	count: Int
	total: Int

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var valid = 0
	var malformed = 0
	var debug = 0
	var info = 0
	var warn = 0
	var err = 0
	var s2 = 0
	var s3 = 0
	var s4 = 0
	var s5 = 0
	var so = 0
	var lats = List[Int]()
	var best = -1
	var best_line = ""
	var counts = Map[String, Int]()
	var sums = Map[String, Int]()
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		f := line.split(" ")
		if f.length() != 6:
			malformed += 1
			continue
		lat := f.get(5, "")
		st := f.get(4, "")
		path := f.get(3, "")
		if f.get(0, "").length() == 0 or not is_level(f.get(1, "")) or not is_method(f.get(2, "")) or not path.starts_with("/") or st.length() != 3 or not all_digits(st) or lat.length() == 0 or lat.length() > 9 or not all_digits(lat):
			malformed += 1
			continue
		valid += 1
		l := f.get(1, "")
		if l == "DEBUG": debug += 1
		else if l == "INFO": info += 1
		else if l == "WARN": warn += 1
		else: err += 1
		d := st.slice(0, 1).get("")
		if d == "2": s2 += 1
		else if d == "3": s3 += 1
		else if d == "4": s4 += 1
		else if d == "5": s5 += 1
		else: so += 1
		n := lat.parse_int().get(0)
		lats.append(n)
		if n > best:
			best = n
			best_line = "{lat} {f.get(2, "")} {path} {f.get(0, "")}"
		counts[path.clone()] = counts.get_or(path, 0) + 1
		sums[path.clone()] = sums.get_or(path, 0) + n
	print("valid: {valid}")
	print("malformed: {malformed}")
	print("DEBUG: {debug}")
	print("INFO: {info}")
	print("WARN: {warn}")
	print("ERROR: {err}")
	print("status: 2xx={s2} 3xx={s3} 4xx={s4} 5xx={s5} other={so}")
	lats.sort()
	if valid == 0:
		print("p95: 0")
	else:
		print("p95: {lats.get((95 * valid + 99) / 100 - 1, 0)}")
		print("slowest: {best_line}")
	print("top:")
	var rows = List[Row]()
	for e in counts.entries():
		rows.append(Row(e.key.clone(), e.value, sums.get_or(e.key, 0)))
	rows.sort(fn(a: Row, b: Row) Int: if a.count != b.count: b.count - a.count else: (if a.path < b.path: -1 else: (if a.path > b.path: 1 else: 0)))
	for i in 0..3:
		if i >= rows.length(): break
		r := rows.get(i)
		print("{r.path} {r.count} avg={r.total / r.count}")
