from "@std/io.ms" import stdin
from "@std/io.ms" import stdout
from "@std/io.ms" import read_all
from "@std/collections.ms" import range
from "@std/bytes.ms" import Bytes

# Byte values of the grid characters. Validation works on bytes so that
# columns are counted in characters: every byte before the first invalid
# one is ASCII, so byte offsets and character offsets agree up to there.
let NEWLINE = 10
let WALL = 35
let OPEN = 46
let START = 83
let GOAL = 69

def is_cell(b: Int) -> Bool:
    return b == WALL or b == OPEN or b == START or b == GOAL

def solve(data: Bytes) -> String:
    var end = data.length()
    while end > 0 and data.get(end - 1) == NEWLINE:
        end -= 1

    var row = 0
    var col = 0

    for i in range(0, end):
        let b = data.get(i)

        if b == NEWLINE:
            row += 1
            col = 0
        else:
            if not is_cell(b):
                return f"error: bad character at {row + 1},{col + 1}"

            col += 1

    var cells: List[Int] = []
    var lengths: List[Int] = []
    var length = 0

    for i in range(0, end):
        let b = data.get(i)

        if b == NEWLINE:
            lengths.append(length)
            length = 0
        else:
            cells.append(b)
            length += 1

    lengths.append(length)

    let width = lengths.get(0)
    for n in range(0, lengths.length()):
        if lengths.get(n) != width:
            return "error: ragged grid"

    var starts = 0
    var goals = 0
    var start = 0
    var goal = 0

    for k in range(0, cells.length()):
        let b = cells.get(k)

        if b == START:
            starts += 1
            start = k

        if b == GOAL:
            goals += 1
            goal = k

    if starts == 0:
        return "error: no start"
    if starts > 1:
        return "error: multiple starts"
    if goals == 0:
        return "error: no end"
    if goals > 1:
        return "error: multiple ends"

    let rows = lengths.length()
    var dist: List[Int] = []
    for k in range(0, cells.length()):
        dist.append(-1)
    dist.set(start, 0)

    var queue: List[Int] = [start]
    var head = 0
    let dr = [-1, 1, 0, 0]
    let dc = [0, 0, -1, 1]

    while head < queue.length():
        let cur = queue.get(head)
        head += 1
        if cur == goal:
            return f"{dist.get(cur)}"

        let r = cur / width
        let c = cur % width

        for d in range(0, 4):
            let nr = r + dr.get(d)
            let nc = c + dc.get(d)

            if nr >= 0 and nr < rows and nc >= 0 and nc < width:
                let next = nr * width + nc

                if cells.get(next) != WALL and dist.get(next) < 0:
                    dist.set(next, dist.get(cur) + 1)
                    queue.append(next)

    return "no path"

export def main() -> Int:
    let data = read_all(stdin()).get()
    stdout().write(f"{solve(data)}\n").get()
    stdout().flush().get()
    return 0
