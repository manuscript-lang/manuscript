import stdin, stdout from "@std/io.ms"
import max, min from "@std/math.ms"
import read_lines from "@std/streams.ms"

type Script:
    kinds: List[Int]
    texts: List[String]

# LCS lengths of every suffix pair, flattened: table[i * (m + 1) + j] is L(i, j).
fn suffix_lcs(a: List[String], b: List[String]) List[Int]:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    var table = List[Int]()
    for k in 0..(n + 1) * w:
        table.append(0)

    for k in 0..n:
        let i = n - 1 - k

        for l in 0..m:
            let j = m - 1 - l

            if a[i] == b[j]:
                table[i * w + j] = table[(i + 1) * w + j + 1] + 1
            else if table[(i + 1) * w + j] >= table[i * w + j + 1]:
                table[i * w + j] = table[(i + 1) * w + j]
            else:
                table[i * w + j] = table[i * w + j + 1]

    return table

# Walks the edit script exactly as the spec's rules describe. Kind 0 is unchanged, 1 deletion, 2 insertion.
fn edit_script(a: List[String], b: List[String]) Script:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    let table = suffix_lcs(a, b)
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
        else if j == m or (i < n and table[(i + 1) * w + j] >= table[i * w + j + 1]):
            kinds.append(1)
            texts.append(a[i].clone())
            i += 1
        else:
            kinds.append(2)
            texts.append(b[j].clone())
            j += 1

    return Script(kinds: kinds, texts: texts)

fn range_text(start: Int, length: Int) String:
    if length == 1:
        return "{start}"

    return "{start},{length}"

export fn main() Int:
    let lines = read_lines(stdin()).get()
    let header = lines[0].split(" ")
    let name_a = header[0]
    let name_b = header[1]
    let context = header[2].parse_int().get(0)
    let n = header[3].parse_int().get(0)
    let m = header[4].parse_int().get(0)
    var a = List[String]()
    var b = List[String]()
    for k in 0..n:
        a.append(lines[1 + k].clone())
    for k in 0..m:
        b.append(lines[1 + n + k].clone())

    let script = edit_script(a, b)
    let kinds = script.kinds
    let texts = script.texts
    let total = kinds.length()
    var changes = List[Int]()
    for p in 0..total:
        if kinds[p] != 0:
            changes.append(p)
    if changes.length() == 0:
        return 0

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

        let s = max(0, first - context)
        let e = min(total - 1, last + context)
        var a_before = 0
        var b_before = 0

        for p in 0..s:
            if kinds[p] != 2:
                a_before += 1
            if kinds[p] != 1:
                b_before += 1

        var len_a = 0
        var len_b = 0

        for p in s..e + 1:
            if kinds[p] != 2:
                len_a += 1
            if kinds[p] != 1:
                len_b += 1

        let start_a = if len_a > 0: a_before + 1 else: a_before

        let start_b = if len_b > 0: b_before + 1 else: b_before

        out.append("@@ -{range_text(start_a, len_a)} +{range_text(start_b, len_b)} @@")

        for p in s..e + 1:
            if kinds[p] == 0:
                out.append(" {texts[p]}")
            else if kinds[p] == 1:
                out.append("-{texts[p]}")
            else:
                out.append("+{texts[p]}")

        g = h

    stdout().write(out.join("\n") + "\n").get()
    return 0
