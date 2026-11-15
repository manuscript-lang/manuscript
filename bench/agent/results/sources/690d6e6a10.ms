import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var rows = List[List[String]]()
	for line in text.lines():
		rows.append(line.clone().chars())
	while rows.length() > 0 and rows.get(rows.length() - 1, List[String]()).length() == 0:
		rows.pop()
	var sr = -1
	var sc = -1
	var er = -1
	var ec = -1
	var starts = 0
	var ends = 0
	for r in 0..rows.length():
		row := rows.get(r, List[String]())
		for c in 0..row.length():
			ch := row.get(c, "")
			if ch != "#" and ch != "." and ch != "S" and ch != "E":
				print("error: bad character at {r + 1},{c + 1}")
				return ok(unit)
	w := if rows.length() > 0: rows.get(0, List[String]()).length() else: 0
	for r in 0..rows.length():
		if rows.get(r, List[String]()).length() != w:
			print("error: ragged grid")
			return ok(unit)
	for r in 0..rows.length():
		row := rows.get(r, List[String]())
		for c in 0..w:
			ch := row.get(c, "")
			if ch == "S":
				starts += 1
				sr = r
				sc = c
			else if ch == "E":
				ends += 1
				er = r
				ec = c
	if starts == 0:
		print("error: no start")
		return ok(unit)
	if starts > 1:
		print("error: multiple starts")
		return ok(unit)
	if ends == 0:
		print("error: no end")
		return ok(unit)
	if ends > 1:
		print("error: multiple ends")
		return ok(unit)
	h := rows.length()
	var dist = List[Int]()
	for _i in 0..(h * w):
		dist.append(-1)
	var queue = List[Int]()
	dist[sr * w + sc] = 0
	queue.append(sr * w + sc)
	var head = 0
	while head < queue.length():
		cur := queue.get(head, 0)
		head += 1
		r := cur / w
		c := cur % w
		d := dist.get(cur, 0)
		for k in 0..4:
			nr := if k == 0: r - 1 else if k == 1: r + 1 else: r
			nc := if k == 2: c - 1 else if k == 3: c + 1 else: c
			if nr < 0 or nr >= h or nc < 0 or nc >= w: continue
			if rows.get(nr, List[String]()).get(nc, "#") == "#": continue
			idx := nr * w + nc
			if dist.get(idx, 0) != -1: continue
			dist[idx] = d + 1
			queue.append(idx)
	res := dist.get(er * w + ec, -1)
	if res < 0:
		print("no path")
	else:
		print("{res}")
