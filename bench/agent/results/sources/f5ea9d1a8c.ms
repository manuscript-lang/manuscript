import stdin from "@std/io.ms"
import stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import range from "@std/collections.ms"

# Formats a hunk range: `start`, `start,length`, or `start,0`.
fn span(start: Int, length: Int) String:
    if length == 1: return "{start}"

    return "{start},{length}"

export fn main() Int:
    let lines = read_lines(stdin()).get()
    let header = lines[0].split(" ")
    let name_a = header[0]
    let name_b = header[1]
    let context = header[2].parse_int().get(0)
    let n = header[3].parse_int().get(0)
    let m = header[4].parse_int().get(0)

    # Line i of A is lines[1 + i]; line j of B is lines[1 + n + j].
    let cols = m + 1
    var table = List[Int]()
    for k in range(0, (n + 1) * cols):
        table.append(0)

    for k in range(0, n):
        let i = n - 1 - k

        for l in range(0, m):
            let j = m - 1 - l

            if lines[1 + i] == lines[1 + n + j]:
                table[i * cols + j] = table[(i + 1) * cols + j + 1] + 1
            else:
                let down = table[(i + 1) * cols + j]
                let right = table[i * cols + j + 1]

                if down >= right:
                    table[i * cols + j] = down
                else:
                    table[i * cols + j] = right

    # Walk the edit script. Kind 0 is unchanged, 1 a deletion from A, 2 an insertion from B.
    var kinds = List[Int]()
    var texts = List[String]()
    var x = 0
    var y = 0

    while x < n or y < m:
        if x < n and y < m and lines[1 + x] == lines[1 + n + y]:
            kinds.append(0)
            texts.append(lines[1 + x])
            x += 1
            y += 1
        else:
            if (
                y == m
                or (
                    x < n
                    and table[(x + 1) * cols + y] >= table[
                        x * cols + y + 1
                    ]
                )
            ):
                kinds.append(1)
                texts.append(lines[1 + x])
                x += 1
            else:
                kinds.append(2)
                texts.append(lines[1 + n + y])
                y += 1

    let total = kinds.length()
    var changes = List[Int]()
    for k in range(0, total):
        if kinds[k] != 0:
            changes.append(k)
    if changes.length() == 0:
        return 0

    # Number of A and B lines consumed before each script position.
    var a_before = List[Int]()
    var b_before = List[Int]()
    a_before.append(0)
    b_before.append(0)

    for k in range(0, total):
        var da = 0
        var db = 0
        if kinds[k] != 2:
            da = 1
        if kinds[k] != 1:
            db = 1
        a_before.append(a_before[k] + da)
        b_before.append(b_before[k] + db)

    var out = List[String]()
    out.append("--- {name_a}")
    out.append("+++ {name_b}")

    var g = 0

    while g < changes.length():
        let first = changes[g]
        var last = first
        var h = g + 1

        while h < changes.length() and changes[h] - last - 1 <= 2 * context:
            last = changes[h]
            h += 1

        let start = max_of_two(0, first - context)
        let end = min_of_two(total - 1, last + context)
        var la = 0
        var lb = 0

        for k in range(start, end + 1):
            if kinds[k] != 2:
                la += 1
            if kinds[k] != 1:
                lb += 1

        var sa = a_before[start]
        var sb = b_before[start]
        if la > 0:
            sa += 1
        if lb > 0:
            sb += 1
        out.append("@@ -{span(sa, la)} +{span(sb, lb)} @@")

        for k in range(start, end + 1):
            let text = texts[k]

            if kinds[k] == 0:
                out.append(" {text}")
            else:
                if kinds[k] == 1:
                    out.append("-{text}")
                else:
                    out.append("+{text}")

        g = h

    let body = out.join("\n")
    stdout().write("{body}\n").get()
    return 0

fn max_of_two(a: Int, b: Int) Int:
    if a >= b: return a

    return b

fn min_of_two(a: Int, b: Int) Int:
    if a <= b: return a

    return b
