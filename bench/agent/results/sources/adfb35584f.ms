import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().ok_or(Error("invalid utf8"))?
	var lines = text.lines().clone()
	while lines.length() > 0 and lines[lines.length() - 1] == "":
		lines.pop()
	var rows: List[List[String]] = []
	for line in lines:
		rows.append(line.chars().clone())
	for r in 0..rows.length():
		for c in 0..rows[r].length():
			ch := rows[r][c]
			if ch != "#" and ch != "." and ch != "S" and ch != "E":
				print("error: bad character at {r + 1},{c + 1}")
				return ok(unit)
	h := rows.length()
	w := if h > 0: rows[0].length() else: 0
	for r in 0..h:
		if rows[r].length() != w:
			print("error: ragged grid")
			return ok(unit)
	var ns = 0
	var ne = 0
	var sr = 0
	var sc = 0
	for r in 0..h:
		for c in 0..w:
			if rows[r][c] == "S":
				ns += 1
				sr = r
				sc = c
			if rows[r][c] == "E":
				ne += 1
	if ns == 0:
		print("error: no start")
		return ok(unit)
	if ns > 1:
		print("error: multiple starts")
		return ok(unit)
	if ne == 0:
		print("error: no end")
		return ok(unit)
	if ne > 1:
		print("error: multiple ends")
		return ok(unit)
	var dist: List[Int] = []
	for i in 0..(h * w):
		dist.append(-1)
	var q: List[Int] = [sr * w + sc]
	dist[sr * w + sc] = 0
	var head = 0
	dr := [-1, 1, 0, 0]
	dc := [0, 0, -1, 1]
	while head < q.length():
		cur := q[head]
		head += 1
		r := cur / w
		c := cur % w
		if rows[r][c] == "E":
			print(dist[cur])
			return ok(unit)
		for k in 0..4:
			nr := r + dr[k]
			nc := c + dc[k]
			if nr < 0 or nc < 0 or nr >= h or nc >= w:
				continue
			if rows[nr][nc] == "#":
				continue
			ni := nr * w + nc
			if dist[ni] >= 0:
				continue
			dist[ni] = dist[cur] + 1
			q.append(ni)
	print("no path")
