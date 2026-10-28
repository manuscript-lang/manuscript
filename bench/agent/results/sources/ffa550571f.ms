import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"

fn fail(msg: String) Int:
    stdout().write("error: {msg}\n").get()
    return 0

export fn main() Int:
    let dr = [-1, 1, 0, 0]
    let dc = [0, 0, -1, 1]
    let rows = read_lines(stdin()).get()
    var n = rows.length()
    while n > 0 and rows[n - 1] == "":
        n -= 1
    if n == 0:
        return fail("no start")

    for r in 0..n:
        let chars = rows[r].chars()

        for c in 0..chars.length():
            let ch = chars[c]
            if ch != "#" and ch != "." and ch != "S" and ch != "E":
                return fail("bad character at {r + 1},{c + 1}")

    let width = rows[0].scalar_length()
    for r in 0..n:
        if rows[r].scalar_length() != width:
            return fail("ragged grid")

    var cells = List[String]()
    for r in 0..n:
        for ch in rows[r].chars():
            cells.append(ch)

    var starts = 0
    var start = 0
    var goals = 0
    var goal = 0

    for i in 0..cells.length():
        if cells[i] == "S":
            starts += 1
            start = i

        if cells[i] == "E":
            goals += 1
            goal = i

    if starts == 0:
        return fail("no start")
    if starts > 1:
        return fail("multiple starts")
    if goals == 0:
        return fail("no end")
    if goals > 1:
        return fail("multiple ends")

    var dist = List[Int]()
    for i in 0..cells.length():
        dist.append(-1)
    dist[start] = 0

    var queue = List[Int]()
    queue.append(start)

    var head = 0

    while head < queue.length():
        let cur = queue[head]
        head += 1

        let r = cur / width
        let c = cur % width

        for d in 0..4:
            let nr = r + dr[d]
            let nc = c + dc[d]
            if nr < 0 or nr >= n or nc < 0 or nc >= width:
                continue

            let nb = nr * width + nc
            if cells[nb] == "#" or dist[nb] != -1:
                continue

            dist[nb] = dist[cur] + 1

            if nb == goal:
                stdout().write("{dist[nb]}\n").get()
                return 0

            queue.append(nb)

    stdout().write("no path\n").get()
    return 0
