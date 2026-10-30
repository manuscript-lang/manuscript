import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

fn emit(text: String) Int:
    stdout().write("{text}\n").get()
    return 0

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var rows = lines.length()

    # Trailing empty lines are not part of the grid.
    while rows > 0 and lines[rows - 1] == "":
        rows -= 1
    if rows == 0:
        return emit("error: no start")

    var grid = List[List[String]]()
    for r in 0..rows:
        grid.append(lines[r].chars())

    # Bad characters are reported first, in reading order, before any shape checks.
    for r in 0..rows:
        for c in 0..grid[r].length():
            let ch = grid[r][c]
            if ch != "#" and ch != "." and ch != "S" and ch != "E":
                return emit("error: bad character at {r + 1},{c + 1}")

    let width = grid[0].length()
    for r in 0..rows:
        if grid[r].length() != width:
            return emit("error: ragged grid")

    var starts = 0
    var ends = 0
    var start = 0
    var end = 0

    for r in 0..rows:
        for c in 0..width:
            if grid[r][c] == "S":
                starts += 1
                start = r * width + c
            else if grid[r][c] == "E":
                ends += 1
                end = r * width + c

    if starts == 0:
        return emit("error: no start")
    if starts > 1:
        return emit("error: multiple starts")
    if ends == 0:
        return emit("error: no end")
    if ends > 1:
        return emit("error: multiple ends")

    # Breadth-first search over the grid; `dist` is -1 for unvisited cells.
    let total = rows * width
    var dist = List[Int]()
    for i in 0..total:
        dist.append(-1)

    var queue = List[Int]()
    queue.append(start)
    dist[start] = 0

    var head = 0

    while head < queue.length():
        let cur = queue[head]
        head += 1
        if cur == end:
            break

        let r = cur / width
        let c = cur % width

        for k in 0..4:
            var nr = r
            var nc = c

            if k == 0:
                nr -= 1
            else if k == 1:
                nr += 1
            else if k == 2:
                nc -= 1
            else:
                nc += 1

            if nr < 0 or nr >= rows or nc < 0 or nc >= width:
                continue

            let next = nr * width + nc
            if grid[nr][nc] == "#" or dist[next] >= 0:
                continue

            dist[next] = dist[cur] + 1
            queue.append(next)

    if dist[end] < 0:
        return emit("no path")

    return emit("{dist[end]}")
