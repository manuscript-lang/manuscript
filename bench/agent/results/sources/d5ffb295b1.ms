import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

# kind 0 is an unchanged line, 1 a deletion from A, 2 an insertion from B
type Edit:
    kind: Int
    text: String

fn line_at(lines: List[String], k: Int) String:
    if k < lines.length():
        return lines[k].clone()

    return ""

fn edit_script(a: List[String], b: List[String]) List[Edit]:
    let n = a.length()
    let m = b.length()
    let w = m + 1

    # lcs[i * w + j] is the LCS length of a[i..] and b[j..]
    var lcs = List[Int]()
    for _k in 0..(n + 1) * w:
        lcs.append(0)

    for r in 0..n:
        let i = n - 1 - r

        for s in 0..m:
            let j = m - 1 - s

            if a[i] == b[j]:
                lcs[i * w + j] = lcs[(i + 1) * w + j + 1] + 1
            else:
                let down = lcs[(i + 1) * w + j]
                let right = lcs[i * w + j + 1]
                lcs[i * w + j] = if down >= right: down else: right

    var out = List[Edit]()
    var i = 0
    var j = 0

    while i < n or j < m:
        if i < n and j < m and a[i] == b[j]:
            out.append(Edit(kind: 0, text: a[i].clone()))
            i += 1
            j += 1
        else if j == m or (i < n and lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]):
            out.append(Edit(kind: 1, text: a[i].clone()))
            i += 1
        else:
            out.append(Edit(kind: 2, text: b[j].clone()))
            j += 1

    return out

fn span(start: Int, length: Int) String:
    if length == 1:
        return "{start}"

    return "{start},{length}"

export fn main() Int:
    let lines = read_lines(stdin()).get()
    let header = lines[0].split(" ")
    let name_a = header[0].clone()
    let name_b = header[1].clone()
    let context = header[2].parse_int().get(0)
    let n = header[3].parse_int().get(0)
    let m = header[4].parse_int().get(0)
    var a = List[String]()
    var b = List[String]()
    for k in 0..n:
        a.append(line_at(lines, 1 + k))
    for k in 0..m:
        b.append(line_at(lines, 1 + n + k))

    let edits = edit_script(a, b)
    let total = edits.length()

    # script positions of every deletion and insertion
    var changes = List[Int]()
    for e in 0..total:
        if edits[e].kind != 0:
            changes.append(e)
    if changes.length() == 0:
        return 0

    # a_before[e] and b_before[e] count the lines of A and B consumed before edit e
    var a_before = List[Int]()
    var b_before = List[Int]()
    var ca = 0
    var cb = 0

    for e in 0..total:
        a_before.append(ca)
        b_before.append(cb)
        if edits[e].kind != 2:
            ca += 1
        if edits[e].kind != 1:
            cb += 1

    var out = List[String]()
    out.append("--- {name_a}")
    out.append("+++ {name_b}")

    var g = 0

    while g < changes.length():
        var last = g
        while (
            last + 1 < changes.length()
            and changes[last + 1] - changes[last] - 1 <= 2 * context
        ):
            last += 1

        var start = changes[g] - context
        if start < 0:
            start = 0

        var stop = changes[last] + context
        if stop >= total:
            stop = total - 1

        var la = 0
        var lb = 0

        for e in start..stop + 1:
            if edits[e].kind != 2:
                la += 1
            if edits[e].kind != 1:
                lb += 1

        let sa = a_before[start] + (if la > 0: 1 else: 0)
        let sb = b_before[start] + (if lb > 0: 1 else: 0)
        out.append("@@ -" + span(sa, la) + " +" + span(sb, lb) + " @@")

        for e in start..stop + 1:
            var prefix = " "

            if edits[e].kind == 1:
                prefix = "-"
            else if edits[e].kind == 2:
                prefix = "+"

            out.append(prefix + edits[e].text)

        g = last + 1

    stdout().write(out.join("\n") + "\n").get()
    return 0
