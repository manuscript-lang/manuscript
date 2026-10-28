import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

fn emit(text: String) Unit:
    stdout().write("{text}\n").get()

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var rows = lines.length()
    while rows > 0 and lines[rows - 1].length() == 0:
        rows -= 1

    if rows == 0:
        emit("error: no start")
        return 0

    var grid = List[List[String]](reserve: rows)

    for r in 0..rows:
        let cells = lines[r].chars()

        for c in 0..cells.length():
            let ch = cells[c]

            if ch != "#" and ch != "." and ch != "S" and ch != "E":
                emit("error: bad character at {r + 1},{c + 1}")
                return 0

        grid.append(cells)

    let width = grid[0].length()

    for r in 0..rows:
        if grid[r].length() != width:
            emit("error: ragged grid")
            return 0

    var starts = 0
    var ends = 0
    var start = 0
    var end = 0

    for r in 0..rows:
        for c in 0..width:
            let ch = grid[r][c]

            if ch == "S":
                starts += 1
                start = r * width + c
            else if ch == "E":
                ends += 1
                end = r * width + c

    if starts == 0:
        emit("error: no start")
        return 0

    if starts > 1:
        emit("error: multiple starts")
        return 0

    if ends == 0:
        emit("error: no end")
        return 0

    if ends > 1:
        emit("error: multiple ends")
        return 0

    let total = rows * width
    var dist = List[Int](reserve: total)
    for i in 0..total:
        dist.append(-1)

    let dr = [-1, 1, 0, 0]
    let dc = [0, 0, -1, 1]
    var queue = List[Int](reserve: total)
    dist[start] = 0
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

            if nr >= 0 and nr < rows and nc >= 0 and nc < width:
                let ni = nr * width + nc

                if grid[nr][nc] != "#" and dist[ni] < 0:
                    dist[ni] = dist[cur] + 1
                    queue.append(ni)

    if dist[end] < 0:
        emit("no path")
    else:
        emit("{dist[end]}")

    return 0
