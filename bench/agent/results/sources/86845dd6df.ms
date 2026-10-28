import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

# Returns line `index`, or "" when the input ended early (a final empty line may lack its terminator).
fn line_at(lines: List[String], index: Int) String:
    if index < lines.length(): return lines[index].clone()

    return ""

fn max_of(x: Int, y: Int) Int:
    if x > y: return x

    return y

fn min_of(x: Int, y: Int) Int:
    if x < y: return x

    return y

# Formats a hunk range: the length is omitted when it is exactly 1.
fn span(start: Int, length: Int) String:
    if length == 1: return "{start}"

    return "{start},{length}"

export fn main() Int:
    let lines = read_lines(stdin()).get()
    let head = lines[0].split(" ")
    let name_a = head[0]
    let name_b = head[1]
    let context = head[2].parse_int().get(0)
    let n = head[3].parse_int().get(0)
    let m = head[4].parse_int().get(0)
    var a = List[String]()
    for i in 0..n:
        a.append(line_at(lines, 1 + i))

    var b = List[String]()
    for j in 0..m:
        b.append(line_at(lines, 1 + n + j))

    # table[i * width + j] is L(i, j), the LCS length of a[i..] and b[j..].
    let width = m + 1
    var table = List[Int](reserve: (n + 1) * width)
    for k in 0..(n + 1) * width:
        table.append(0)

    for ii in 0..n:
        let i = n - 1 - ii

        for jj in 0..m:
            let j = m - 1 - jj

            if a[i] == b[j]:
                table[i * width + j] = table[(i + 1) * width + j + 1] + 1
            else:
                let down = table[(i + 1) * width + j]
                let right = table[i * width + j + 1]
                table[i * width + j] = if down >= right: down else: right

    # Edit script: kind 0 is unchanged, 1 is a deletion from a, 2 is an insertion from b.
    var kinds = List[Int]()
    var texts = List[String]()
    var i = 0
    var j = 0

    while i < n or j < m:
        if i < n and j < m and a[i] == b[j]:
            kinds.append(0)
            texts.append(a[i].clone())
            i += 1
            j += 1
        else if (
            j == m
            or (
                i < n
                and table[(i + 1) * width + j] >= table[
                    i * width + j + 1
                ]
            )
        ):
            kinds.append(1)
            texts.append(a[i].clone())
            i += 1
        else:
            kinds.append(2)
            texts.append(b[j].clone())
            j += 1

    let total = kinds.length()

    # pre_a[k] and pre_b[k] count the lines of a and b consumed before script position k.
    var pre_a = List[Int]()
    var pre_b = List[Int]()
    var count_a = 0
    var count_b = 0

    for k in 0..total:
        pre_a.append(count_a)
        pre_b.append(count_b)
        if kinds[k] != 2:
            count_a += 1
        if kinds[k] != 1:
            count_b += 1

    pre_a.append(count_a)
    pre_b.append(count_b)

    # Group changes into hunks, each widened by up to `context` unchanged lines on either side.
    var hunk_lo = List[Int]()
    var hunk_hi = List[Int]()
    var first = -1
    var last = -1

    for k in 0..total:
        if kinds[k] == 0:
            continue

        if first < 0:
            first = k
            last = k
        else if k - last - 1 <= 2 * context:
            last = k
        else:
            hunk_lo.append(max_of(first - context, 0))
            hunk_hi.append(min_of(last + context, total - 1))
            first = k
            last = k

    if first < 0:
        return 0

    hunk_lo.append(max_of(first - context, 0))
    hunk_hi.append(min_of(last + context, total - 1))

    var out = List[String]()
    out.append("--- {name_a}")
    out.append("+++ {name_b}")

    for h in 0..hunk_lo.length():
        let lo = hunk_lo[h]
        let hi = hunk_hi[h]
        let la = pre_a[hi + 1] - pre_a[lo]
        let lb = pre_b[hi + 1] - pre_b[lo]

        let sa = if la > 0: pre_a[lo] + 1 else: pre_a[lo]

        let sb = if lb > 0: pre_b[lo] + 1 else: pre_b[lo]

        out.append("@@ -{span(sa, la)} +{span(sb, lb)} @@")

        for q in lo..hi + 1:
            if kinds[q] == 0:
                out.append(" {texts[q]}")
            else if kinds[q] == 1:
                out.append("-{texts[q]}")
            else:
                out.append("+{texts[q]}")

    let text = out.join("\n")
    stdout().write("{text}\n").get()
    return 0
