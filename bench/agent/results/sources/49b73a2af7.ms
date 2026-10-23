import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"
import {range} from "@std/collections.ms"

# One script line: kind 0 is unchanged, 1 is a deletion from A, 2 is an insertion from B.
type Op:
    kind: Int
    text: String

# L(i, j) for suffixes, stored row-major with width b.length() + 1.
fn lcs_table(a: List[String], b: List[String]) List[Int]:
    let w = b.length() + 1
    var t: List[Int] = []
    for k in range(0, (a.length() + 1) * w):
        t.append(0)

    for x in range(0, a.length()):
        let i = a.length() - 1 - x

        for y in range(0, b.length()):
            let j = b.length() - 1 - y

            if a[i] == b[j]:
                t[i * w + j] = t[(i + 1) * w + j + 1] + 1
            else:
                let down = t[(i + 1) * w + j]
                let right = t[i * w + j + 1]

                if down >= right:
                    t[i * w + j] = down
                else:
                    t[i * w + j] = right

    return t

fn edit_script(a: List[String], b: List[String], t: List[Int]) List[Op]:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    var ops: List[Op] = []
    var i = 0
    var j = 0

    for k in range(0, n + m):
        if i == n and j == m:
            return ops

        if i == n:
            ops.append(Op(2, b[j]))
            j += 1
        else if j == m:
            ops.append(Op(1, a[i]))
            i += 1
        else if a[i] == b[j]:
            ops.append(Op(0, a[i]))
            i += 1
            j += 1
        else if t[(i + 1) * w + j] >= t[i * w + j + 1]:
            ops.append(Op(1, a[i]))
            i += 1
        else:
            ops.append(Op(2, b[j]))
            j += 1

    return ops

# Start line of a hunk section given the lines consumed before it.
fn hunk_start(before: Int, length: Int) Int:
    if length > 0: return before + 1

    return before

fn hunk_span(start: Int, length: Int) String:
    if length == 1: return "{start}"

    return "{start},{length}"

export fn main() Int:
    let lines = read_lines(stdin()).get()
    let head = lines[0].split(" ")
    let name_a = head[0]
    let name_b = head[1]
    let ctx = head[2].parse_int().get()
    let n = head[3].parse_int().get()
    let m = head[4].parse_int().get()
    var a: List[String] = []
    var b: List[String] = []
    for i in range(0, n):
        a.append(lines[1 + i])
    for j in range(0, m):
        b.append(lines[1 + n + j])

    let ops = edit_script(a, b, lcs_table(a, b))
    let total = ops.length()

    # apre[p] and bpre[p] count the A and B lines consumed by the first p script lines.
    var apre = [0]
    var bpre = [0]

    for p in range(0, total):
        var da = 1
        if ops[p].kind == 2: da = 0

        var db = 1
        if ops[p].kind == 1: db = 0
        apre.append(apre[p] + da)
        bpre.append(bpre[p] + db)

    # Group changes into runs: a gap of unchanged lines above 2 * ctx starts a new hunk.
    var starts: List[Int] = []
    var ends: List[Int] = []
    var first = -1
    var last = -1

    for p in range(0, total):
        if ops[p].kind != 0:
            if last < 0:
                first = p
            else if p - last - 1 > 2 * ctx:
                starts.append(first)
                ends.append(last)
                first = p

            last = p

    if last >= 0:
        starts.append(first)
        ends.append(last)

    if starts.length() == 0:
        return 0

    var out: List[String] = []
    out.append("--- {name_a}\n+++ {name_b}\n")

    for h in range(0, starts.length()):
        var lo = starts[h] - ctx
        if lo < 0: lo = 0

        var hi = ends[h] + ctx + 1
        if hi > total: hi = total

        let la = apre[hi] - apre[lo]
        let lb = bpre[hi] - bpre[lo]
        let sa = hunk_span(hunk_start(apre[lo], la), la)
        let sb = hunk_span(hunk_start(bpre[lo], lb), lb)
        out.append("@@ -{sa} +{sb} @@\n")

        for p in range(lo, hi):
            let op = ops[p]

            if op.kind == 0:
                out.append(" {op.text}\n")
            else if op.kind == 1:
                out.append("-{op.text}\n")
            else:
                out.append("+{op.text}\n")

    stdout().write(out.join("")).get()
    return 0
