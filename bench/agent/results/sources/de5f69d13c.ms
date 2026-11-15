import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn solve(text: String) String:
	var rows = List[List[String]]()
	for l in text.lines():
		rows.append(l.chars().clone())
	while rows.length() > 0 and rows.get(rows.length() - 1, ["x"]).length() == 0:
		rows.pop()
	h := rows.length()
	var sr = -1
	var sc = -1
	var er = -1
	var ec = -1
	var ns = 0
	var ne = 0
	for r in 0..h:
		row := rows.get(r, [])
		for c in 0..row.length():
			ch := row.get(c, "")
			if ch != "#" and ch != "." and ch != "S" and ch != "E":
				return "error: bad character at {r + 1},{c + 1}"
	w := if h > 0: rows.get(0, []).length() else: 0
	for r in 0..h:
		if rows.get(r, []).length() != w: return "error: ragged grid"
	for r in 0..h:
		row := rows.get(r, [])
		for c in 0..w:
			ch := row.get(c, "")
			if ch == "S":
				ns += 1
				sr = r
				sc = c
			if ch == "E":
				ne += 1
				er = r
				ec = c
	if ns == 0: return "error: no start"
	if ns > 1: return "error: multiple starts"
	if ne == 0: return "error: no end"
	if ne > 1: return "error: multiple ends"
	var dist = List[Int]()
	for _i in 0..(h * w):
		dist.append(-1)
	var queue = List[Int]()
	queue.append(sr * w + sc)
	dist[sr * w + sc] = 0
	var head = 0
	dr := [1, -1, 0, 0]
	dc := [0, 0, 1, -1]
	while head < queue.length():
		cur := queue.get(head, 0)
		head += 1
		r := cur / w
		c := cur % w
		d := dist.get(cur, 0)
		for k in 0..4:
			nr := r + dr.get(k, 0)
			nc := c + dc.get(k, 0)
			if nr < 0 or nc < 0 or nr >= h or nc >= w: continue
			if rows.get(nr, []).get(nc, "#") == "#": continue
			idx := nr * w + nc
			if dist.get(idx, 0) != -1: continue
			dist[idx] = d + 1
			queue.append(idx)
	res := dist.get(er * w + ec, -1)
	if res < 0: return "no path"
	return "{res}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	print(solve(text))
