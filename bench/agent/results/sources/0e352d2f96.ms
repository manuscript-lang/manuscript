import read_all from "@std/io/streams.ms"
import stdin, stdout from "@std/io/io.ms"

fn out(s: String) Unit:
    stdout().write(s).get()

export fn main() Int:
    let raw = read_all(stdin()).get()
    let text = raw.decode_utf8().get("")
    var rows = text.split("\n")

    // Trailing empty lines are ignored; interior empty lines are rows of width 0.
    var n = rows.length()
    while n > 0 and rows[n - 1].length() == 0:
        n -= 1

    if n == 0:
        out("error: no start\n")
        return 0

    // 1. Bad characters, first in reading order (columns counted in scalars).
    for r in 0..n:
        let cs = rows[r].chars()

        for c in 0..cs.length():
            let ch = cs[c]

            if not (ch == "#" or ch == "." or ch == "S" or ch == "E"):
                out("error: bad character at {r + 1},{c + 1}\n")
                return 0

    // 2. Ragged rows. Every character is now ASCII, so byte length equals scalar length.
    let width = rows[0].length()

    for r in 0..n:
        if rows[r].length() != width:
            out("error: ragged grid\n")
            return 0

    // 3 and 4. Start and end markers.
    var walls = List[Bool]()
    var starts = 0
    var ends = 0
    var s = 0
    var e = 0

    for r in 0..n:
        let cs = rows[r].chars()

        for c in 0..width:
            let ch = cs[c]
            let idx = r * width + c
            walls.append(ch == "#")

            if ch == "S":
                starts += 1
                s = idx
            else if ch == "E":
                ends += 1
                e = idx

    if starts == 0:
        out("error: no start\n")
        return 0

    if starts > 1:
        out("error: multiple starts\n")
        return 0

    if ends == 0:
        out("error: no end\n")
        return 0

    if ends > 1:
        out("error: multiple ends\n")
        return 0

    // Breadth-first search over non-wall cells, 4-directional.
    let total = n * width
    var dist = List[Int]()
    for i in 0..total:
        dist.append(-1)

    var queue = List[Int]()
    queue.append(s)
    dist[s] = 0

    var head = 0

    while head < queue.length():
        let cur = queue[head]
        head += 1
        if cur == e:
            break

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

            if nr < 0 or nr >= n or nc < 0 or nc >= width:
                continue

            let nb = nr * width + nc
            if walls[nb] or dist[nb] >= 0:
                continue

            dist[nb] = dist[cur] + 1
            queue.append(nb)

    if dist[e] < 0:
        out("no path\n")
    else:
        out("{dist[e]}\n")

    return 0
