import Bytes from "@std/bytes.ms"
import {read_all, stdin, stdout} from "@std/io.ms"
import {range} from "@std/collections.ms"

fn is_cell(ch: String) Bool: ch == "#" or ch == "." or ch == "S" or ch == "E"

# Returns the first validation error, or "" when the grid is well formed.
fn validate(grid: List[List[String]]) String:
    for r in range(0, grid.length()):
        for c in range(0, grid[r].length()):
            if not is_cell(grid[r][c]): return "error: bad character at {r + 1},{c + 1}"

    let width = if grid.is_empty(): 0 else: grid[0].length()

    for row in grid:
        if row.length() != width: return "error: ragged grid"

    var starts = 0
    var ends = 0

    for row in grid:
        for ch in row:
            if ch == "S": starts += 1
            if ch == "E": ends += 1

    if starts == 0: return "error: no start"
    if starts > 1: return "error: multiple starts"
    if ends == 0: return "error: no end"
    if ends > 1: return "error: multiple ends"

    return ""

fn solve(text: String) String:
    var lines = text.split("\n")

    while not lines.is_empty() and lines[-1] == "": lines.pop()

    let grid = lines.map(fn(line: String) List[String]: line.chars())
    let error = validate(grid.clone())
    if error != "": return error

    let width = if grid.is_empty(): 0 else: grid[0].length()

    let total = grid.length() * width
    var passable: List[Bool] = []
    var start = 0
    var goal = 0

    for r in range(0, grid.length()):
        for c in range(0, width):
            let ch = grid[r][c]

            passable.append(ch != "#")
            if ch == "S": start = r * width + c
            if ch == "E": goal = r * width + c

    var dist = range(0, total).map(fn(i: Int) Int: -1)
    var queue = [start]

    dist[start] = 0

    var head = 0

    while head < queue.length():
        let cur = queue[head]

        head += 1
        if cur == goal: return "{dist[cur]}"

        let r = cur / width
        let c = cur % width

        if r > 0: visit(cur - width, dist[cur] + 1, passable, var dist, var queue)
        if r + 1 < grid.length(): visit(
            cur + width, dist[cur] + 1, passable, var dist, var queue
        )
        if c > 0: visit(cur - 1, dist[cur] + 1, passable, var dist, var queue)
        if c + 1 < width: visit(cur + 1, dist[cur] + 1, passable, var dist, var queue)

    return "no path"

fn visit(
    next: Int,
    d: Int,
    passable: List[Bool],
    var dist: List[Int],
    var queue: List[Int]
) Unit:
    if passable[next] and dist[next] == -1:
        dist[next] = d
        queue.append(next)

export fn main() Int:
    let bytes = read_all(stdin()).or_else(fn(cause) Bytes: "".to_bytes())
    let text = bytes.decode_utf8().get("")

    stdout().write("{solve(text)}\n").get()
    return 0
