import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Stat:
	path: String
	count: Int = 0
	total: Int = 0

fn all_digits(s: String) Bool:
	if s.length() == 0: return false
	for i in 0..s.length():
		c := s.scalar_at(i)
		if c < 48 or c > 57: return false
	return true

fn cmp(a: Stat, b: Stat) Int:
	if a.count != b.count: return b.count - a.count
	if a.path < b.path: return -1
	if a.path > b.path: return 1
	return 0

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var valid = 0
	var bad = 0
	var lv = [0, 0, 0, 0]
	var st = [0, 0, 0, 0, 0]
	var lats = List[Int]()
	var best = -1
	var best_line = ""
	var idx = Map[String, Int]()
	var stats = List[Stat]()
	for line in lines(stdin()):
		if line.fields().length() == 0: continue
		p := line.split(" ")
		if p.length() != 6:
			bad += 1
			continue
		li := if p[1] == "DEBUG": 0 else if p[1] == "INFO": 1 else if p[1] == "WARN": 2 else if p[1] == "ERROR": 3 else: -1
		okm := p[2] == "GET" or p[2] == "POST" or p[2] == "PUT" or p[2] == "DELETE"
		if p[0].length() == 0 or li < 0 or not okm or p[3].length() == 0 or p[3].scalar_at(0) != 47 or p[4].length() != 3 or not all_digits(p[4]) or not all_digits(p[5]) or p[5].length() > 9:
			bad += 1
			continue
		valid += 1
		lv[li] += 1
		d := p[4].scalar_at(0) - 48
		si := if d >= 2 and d <= 5: d - 2 else: 4
		st[si] += 1
		lat := p[5].parse_int().get(0)
		lats.append(lat)
		if lat > best:
			best = lat
			best_line = "{lat} {p[2]} {p[3]} {p[0]}"
		if k := idx.get(p[3]):
			stats[k].count += 1
			stats[k].total += lat
		else:
			idx[p[3].clone()] = stats.length()
			stats.append(Stat(path: p[3].clone(), count: 1, total: lat))
	print("valid: {valid}")
	print("malformed: {bad}")
	print("DEBUG: {lv[0]}")
	print("INFO: {lv[1]}")
	print("WARN: {lv[2]}")
	print("ERROR: {lv[3]}")
	print("status: 2xx={st[0]} 3xx={st[1]} 4xx={st[2]} 5xx={st[3]} other={st[4]}")
	lats.sort()
	if valid == 0:
		print("p95: 0")
	else:
		print("p95: {lats[(95 * valid + 99) / 100 - 1]}")
		print("slowest: {best_line}")
	print("top:")
	stats.sort(cmp)
	n := if stats.length() < 3: stats.length() else: 3
	for i in 0..n:
		print("{stats[i].path} {stats[i].count} avg={stats[i].total / stats[i].count}")
