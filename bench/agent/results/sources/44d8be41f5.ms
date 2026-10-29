import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

fn say(msg: String) Int:
    stdout().write("{msg}\n").get()
    return 0

export fn main() Int:
    let rows = read_lines(stdin()).get()
    var n = rows.length()

    # Trailing empty lines are not part of the grid.
    while n > 0 and rows[n - 1].length() == 0:
        n -= 1
    if n == 0:
        return say("error: no start")

    var grid = List[List[String]]()
    for r in 0..n:
        grid.append(rows[r].chars())

    for r in 0..n:
        for c in 0..grid[r].length():
            let ch = grid[r][c]
            if ch != "#" and ch != "." and ch != "S" and ch != "E":
                return say("error: bad character at {r + 1},{c + 1}")

    let width = grid[0].length()
    for r in 0..n:
        if grid[r].length() != width:
            return say("error: ragged grid")

    var starts = 0
    var ends = 0
    var s = 0
    var e = 0

    for r in 0..n:
        for c in 0..width:
            let ch = grid[r][c]

            if ch == "S":
                starts += 1
                s = r * width + c
            else if ch == "E":
                ends += 1
                e = r * width + c

    if starts == 0:
        return say("error: no start")
    if starts > 1:
        return say("error: multiple starts")
    if ends == 0:
        return say("error: no end")
    if ends > 1:
        return say("error: multiple ends")

    # Breadth-first search over the flattened grid; -1 means not yet reached.
    var dist = List[Int]()
    for i in 0..n * width:
        dist.append(-1)
    dist[s] = 0

    var queue = List[Int]()
    queue.append(s)

    let dr = [-1, 1, 0, 0]
    let dc = [0, 0, -1, 1]
    var head = 0

    while head < queue.length():
        let cur = queue[head]
        head += 1

        let r = cur / width
        let c = cur % width

        for k in 0..4:
            let nr = r + dr[k]
            let nc = c + dc[k]
            if nr < 0 or nr >= n or nc < 0 or nc >= width:
                continue

            let next = nr * width + nc
            if grid[nr][nc] == "#" or dist[next] != -1:
                continue

            dist[next] = dist[cur] + 1
            queue.append(next)

    if dist[e] < 0:
        return say("no path")

    return say("{dist[e]}")
