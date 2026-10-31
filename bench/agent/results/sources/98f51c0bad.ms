import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

fn report(msg: String) Unit:
    stdout().write("{msg}\n").get()

export fn main() Int:
    let lines = read_lines(stdin()).get()
    # Trailing empty lines are ignored; interior empty lines are rows of width 0.
    var n = lines.length()
    while n > 0 and lines[n - 1].length() == 0:
        n -= 1

    var grid = List[List[String]]()
    for r in 0..n:
        grid.append(lines[r].chars())

    # 1. Bad characters, in reading order.
    for r in 0..n:
        for c in 0..grid[r].length():
            let ch = grid[r][c]
            if ch != "#" and ch != "." and ch != "S" and ch != "E":
                report("error: bad character at {r + 1},{c + 1}")
                return 0

    # 2. Ragged rows.
    var width = 0
    if n > 0:
        width = grid[0].length()
    for r in 0..n:
        if grid[r].length() != width:
            report("error: ragged grid")
            return 0

    # 3 and 4. Start and end cells.
    var starts = 0
    var ends = 0
    var sIdx = 0
    var eIdx = 0
    for r in 0..n:
        for c in 0..width:
            let ch = grid[r][c]
            if ch == "S":
                starts += 1
                sIdx = r * width + c
            else if ch == "E":
                ends += 1
                eIdx = r * width + c

    if starts == 0:
        report("error: no start")
        return 0
    if starts > 1:
        report("error: multiple starts")
        return 0
    if ends == 0:
        report("error: no end")
        return 0
    if ends > 1:
        report("error: multiple ends")
        return 0

    # Breadth-first search over a flat index r * width + c.
    let total = n * width
    var passable = List[Bool]()
    for r in 0..n:
        for c in 0..width:
            passable.append(grid[r][c] != "#")

    var dist = List[Int]()
    for i in 0..total:
        dist.append(-1)

    var queue = List[Int]()
    queue.append(sIdx)
    dist[sIdx] = 0
    var head = 0
    while head < queue.length():
        let cur = queue[head]
        head += 1
        let r = cur / width
        let c = cur % width
        for d in 0..4:
            var nr = r
            var nc = c
            if d == 0:
                nr = r - 1
            else if d == 1:
                nr = r + 1
            else if d == 2:
                nc = c - 1
            else:
                nc = c + 1
            if nr >= 0 and nr < n and nc >= 0 and nc < width:
                let idx = nr * width + nc
                if passable[idx] and dist[idx] < 0:
                    dist[idx] = dist[cur] + 1
                    queue.append(idx)

    if dist[eIdx] < 0:
        report("no path")
    else:
        report("{dist[eIdx]}")
    return 0
