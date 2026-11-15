import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	raw := read_all(stdin())?
	text := raw.decode_utf8().ok_or(Error("invalid utf8"))?
	lines := text.lines()
	var n = lines.length()
	while n > 0 and lines[n - 1].length() == 0:
		n -= 1
	var grid = List[List[String]]()
	for i in 0..n:
		grid.append(lines[i].chars().clone())
	for r in 0..grid.length():
		for c in 0..grid[r].length():
			ch := grid[r][c]
			if ch != "#" and ch != "." and ch != "S" and ch != "E":
				print("error: bad character at {r + 1},{c + 1}")
				return ok(unit)
	for r in 1..grid.length():
		if grid[r].length() != grid[0].length():
			print("error: ragged grid")
			return ok(unit)
	var ns = 0
	var ne = 0
	var sr = 0
	var sc = 0
	var er = 0
	var ec = 0
	for r in 0..grid.length():
		for c in 0..grid[r].length():
			if grid[r][c] == "S":
				ns += 1
				sr = r
				sc = c
			if grid[r][c] == "E":
				ne += 1
				er = r
				ec = c
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
	h := grid.length()
	w := grid[0].length()
	var dist = List[Int]()
	for i in 0..h * w:
		dist.append(-1)
	var queue = List[Int]()
	queue.append(sr * w + sc)
	dist[sr * w + sc] = 0
	var head = 0
	dr := [-1, 1, 0, 0]
	dc := [0, 0, -1, 1]
	while head < queue.length():
		cur := queue[head]
		head += 1
		r := cur / w
		c := cur % w
		for k in 0..4:
			nr := r + dr[k]
			nc := c + dc[k]
			if nr < 0 or nc < 0 or nr >= h or nc >= w:
				continue
			if grid[nr][nc] == "#":
				continue
			id := nr * w + nc
			if dist[id] >= 0:
				continue
			dist[id] = dist[cur] + 1
			queue.append(id)
	d := dist[er * w + ec]
	if d < 0:
		print("no path")
	else:
		print("{d}")
