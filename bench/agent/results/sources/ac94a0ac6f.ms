import (
    stdin from "@std/io/io.ms",
    lines from "@std/io/streams.ms",
)

// ms: allow_effect std.console.read
fn read_rows() List[String]:
    var rows = List[String]()
    var it = lines(stdin())
    var more = true

    while more:
        let item = it.next().get()

        if let line = item:
            rows.append(line)
        else:
            more = false

    return rows

export fn main() Int:
    let all = read_rows()

    // Trailing empty lines are ignored.
    var h = all.length()
    while h > 0 and all[h - 1].length() == 0:
        h -= 1

    // 1. Bad characters, in reading order.
    for r in 0..h:
        let cells = all[r].chars()

        for c in 0..cells.length():
            let ch = cells[c]

            if ch != "#" and ch != "." and ch != "S" and ch != "E":
                let row_no = r + 1
                let col_no = c + 1
                print("error: bad character at {row_no},{col_no}")
                return 0

    // 2. Ragged rows.
    var w = 0
    if h > 0:
        w = all[0].length()

    for r in 0..h:
        if all[r].length() != w:
            print("error: ragged grid")
            return 0

    // Flatten the grid and locate S and E.
    var grid = List[String]()
    var nS = 0
    var nE = 0
    var sr = 0
    var sc = 0
    var er = 0
    var ec = 0

    for r in 0..h:
        let cells = all[r].chars()

        for c in 0..w:
            let ch = cells[c]
            grid.append(ch.clone())

            if ch == "S":
                nS += 1
                sr = r
                sc = c

            if ch == "E":
                nE += 1
                er = r
                ec = c

    // 3. Start and end counts.
    if nS == 0:
        print("error: no start")
        return 0

    if nS > 1:
        print("error: multiple starts")
        return 0

    if nE == 0:
        print("error: no end")
        return 0

    if nE > 1:
        print("error: multiple ends")
        return 0

    // Breadth-first search from S to E.
    let total = h * w
    var dist = List[Int]()
    for i in 0..total:
        dist.append(-1)

    let start = sr * w + sc
    let goal = er * w + ec
    dist[start] = 0

    var queue = List[Int]()
    queue.append(start)

    let dr = [-1, 1, 0, 0]
    let dc = [0, 0, -1, 1]
    var head = 0
    var answer = -1

    while head < queue.length():
        let cur = queue[head]
        head += 1

        if cur == goal:
            answer = dist[cur]
            break

        let r = cur / w
        let c = cur % w

        for k in 0..4:
            let nr = r + dr[k]
            let nc = c + dc[k]

            if nr >= 0 and nr < h and nc >= 0 and nc < w:
                let ni = nr * w + nc

                if grid[ni] != "#" and dist[ni] == -1:
                    dist[ni] = dist[cur] + 1
                    queue.append(ni)

    if answer < 0:
        print("no path")
    else:
        print(answer)

    return 0
