// ms: allow_effect std.console.read
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn solve(text: String) String:
    let all = text.split("\n")
    // Trailing empty lines are ignored.
    var n = all.length()
    while n > 0 and all[n - 1].length() == 0:
        n -= 1

    // Validation 1: bad characters, in reading order.
    var grid = List[List[String]]()
    for r in 0..n:
        let cs = all[r].chars()
        for c in 0..cs.length():
            let ch = cs[c]
            if not (ch == "#" or ch == "." or ch == "S" or ch == "E"):
                return "error: bad character at {r + 1},{c + 1}"
        grid.append(cs)

    // Validation 2: ragged rows.
    let w = if n == 0: 0 else: grid[0].length()
    for r in 0..n:
        if grid[r].length() != w:
            return "error: ragged grid"

    // Validation 3 and 4: start and end counts.
    var starts = 0
    var ends = 0
    var sidx = 0
    var eidx = 0
    var walls = List[Bool]()
    for r in 0..n:
        for c in 0..w:
            let ch = grid[r][c]
            let idx = r * w + c
            walls.append(ch == "#")
            if ch == "S":
                starts += 1
                sidx = idx
            if ch == "E":
                ends += 1
                eidx = idx
    if starts == 0:
        return "error: no start"
    if starts > 1:
        return "error: multiple starts"
    if ends == 0:
        return "error: no end"
    if ends > 1:
        return "error: multiple ends"

    // BFS from S to E.
    let total = n * w
    var dist = List[Int]()
    for i in 0..total:
        dist.append(-1)
    let dr = [-1, 1, 0, 0]
    let dc = [0, 0, -1, 1]
    var queue = List[Int]()
    queue.append(sidx)
    dist[sidx] = 0
    var head = 0
    while head < queue.length():
        let cur = queue[head]
        head += 1
        if cur == eidx:
            break
        let r = cur / w
        let c = cur % w
        for d in 0..4:
            let nr = r + dr[d]
            let nc = c + dc[d]
            if nr < 0 or nr >= n or nc < 0 or nc >= w:
                continue
            let ni = nr * w + nc
            if walls[ni] or dist[ni] != -1:
                continue
            dist[ni] = dist[cur] + 1
            queue.append(ni)

    if dist[eidx] == -1:
        return "no path"
    return "{dist[eidx]}"

export fn main() Int:
    let bytes = read_all(stdin()).get()
    if let text = bytes.decode_utf8():
        print(solve(text))
    else:
        print("error: bad character at 1,1")
    return 0
