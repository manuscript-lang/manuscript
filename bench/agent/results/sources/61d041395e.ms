import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"
import {range} from "@std/collections.ms"

fn say(text: String) Result[Unit, Error]:
    return stdout().write("{text}\n")

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var last = lines.length()
    while last > 0 and lines[last - 1].length() == 0:
        last -= 1
    var grid: List[List[String]] = []
    for r in range(0, last):
        grid.append(lines[r].chars())

    for r in range(0, grid.length()):
        for c in range(0, grid[r].length()):
            let ch = grid[r][c]

            if ch != "#" and ch != "." and ch != "S" and ch != "E":
                say("error: bad character at {r + 1},{c + 1}").get()
                return 0

    var width = 0
    if grid.length() > 0:
        width = grid[0].length()

    for row in grid:
        if row.length() != width:
            say("error: ragged grid").get()
            return 0

    var start = -1
    var end = -1
    var starts = 0
    var ends = 0

    for r in range(0, grid.length()):
        for c in range(0, width):
            let ch = grid[r][c]

            if ch == "S":
                starts += 1
                start = r * width + c

            if ch == "E":
                ends += 1
                end = r * width + c

    if starts == 0:
        say("error: no start").get()
        return 0

    if starts > 1:
        say("error: multiple starts").get()
        return 0

    if ends == 0:
        say("error: no end").get()
        return 0

    if ends > 1:
        say("error: multiple ends").get()
        return 0

    let total = grid.length() * width
    var dist: List[Int] = []
    for i in range(0, total):
        dist.append(-1)
    dist[start] = 0
    var queue: List[Int] = [start]
    var head = 0

    while head < queue.length():
        let cur = queue[head]
        head += 1
        let r = cur / width
        let c = cur % width

        for step in range(0, 4):
            var nr = r
            var nc = c
            if step == 0:
                nr = r - 1
            if step == 1:
                nr = r + 1
            if step == 2:
                nc = c - 1
            if step == 3:
                nc = c + 1
            if nr < 0 or nr >= grid.length() or nc < 0 or nc >= width:
                continue

            let next = nr * width + nc
            if grid[nr][nc] == "#" or dist[next] >= 0:
                continue

            dist[next] = dist[cur] + 1
            queue.append(next)

    if dist[end] < 0:
        say("no path").get()
    else:
        say("{dist[end]}").get()

    return 0
