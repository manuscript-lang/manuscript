import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

# Kinds of script entries.
let SAME = 0
let DEL = 1
let INS = 2

fn range_str(start: Int, len: Int) String:
    if len == 1:
        return "{start}"

    return "{start},{len}"

# Appends the hunk covering script entries [start, end] to `out`.
fn emit_hunk(
    kinds: List[Int],
    texts: List[String],
    var ia: List[Int],
    var jb: List[Int],
    start: Int,
    end: Int,
    var out: List[String]
) Unit:
    var la = 0
    var lb = 0

    for k in start..end + 1:
        if kinds[k] != INS:
            la += 1
        if kinds[k] != DEL:
            lb += 1

    var sa = ia[start]
    if la > 0:
        sa += 1

    var sb = jb[start]
    if lb > 0:
        sb += 1
    out.append("@@ -{range_str(sa, la)} +{range_str(sb, lb)} @@")

    for k in start..end + 1:
        if kinds[k] == SAME:
            out.append(" {texts[k]}")
        else if kinds[k] == DEL:
            out.append("-{texts[k]}")
        else:
            out.append("+{texts[k]}")

export fn main() Int:
    let lines = read_lines(stdin()).get()
    let hdr = lines[0].split(" ")
    let name_a = hdr[0].clone()
    let name_b = hdr[1].clone()
    let ctx = hdr[2].parse_int().get(0)
    let n = hdr[3].parse_int().get(0)
    let m = hdr[4].parse_int().get(0)

    # A line i is lines[1 + i]; B line j is lines[1 + n + j].
    let w = m + 1
    var table = List[Int](reserve: (n + 1) * w)
    for k in 0..(n + 1) * w:
        table.append(0)

    var i = n - 1

    while i >= 0:
        var j = m - 1

        while j >= 0:
            if lines[1 + i] == lines[1 + n + j]:
                table[i * w + j] = table[(i + 1) * w + j + 1] + 1
            else:
                let down = table[(i + 1) * w + j]
                let right = table[i * w + j + 1]
                table[i * w + j] = if down >= right: down else: right

            j -= 1

        i -= 1

    # Walk the edit script.
    var kinds = List[Int]()
    var texts = List[String]()
    i = 0

    var j = 0

    while i < n or j < m:
        if i < n and j < m and lines[1 + i] == lines[1 + n + j]:
            kinds.append(SAME)
            texts.append(lines[1 + i].clone())
            i += 1
            j += 1
        else if j == m or (i < n and table[(i + 1) * w + j] >= table[i * w + j + 1]):
            kinds.append(DEL)
            texts.append(lines[1 + i].clone())
            i += 1
        else:
            kinds.append(INS)
            texts.append(lines[1 + n + j].clone())
            j += 1

    let total = kinds.length()

    # ia[p]: A lines before script entry p; jb[p]: B lines before entry p.
    var ia = List[Int]()
    var jb = List[Int]()
    ia.append(0)
    jb.append(0)

    for p in 0..total:
        var da = 0
        var db = 0
        if kinds[p] != INS:
            da = 1
        if kinds[p] != DEL:
            db = 1
        ia.append(ia[p] + da)
        jb.append(jb[p] + db)

    var out = List[String]()
    var first = -1
    var last = -1
    var p = 0

    while p < total:
        if kinds[p] != SAME:
            if first < 0:
                first = p
                last = p
            else if p - last - 1 <= 2 * ctx:
                last = p
            else:
                let s = if first - ctx > 0: first - ctx else: 0

                let e = if last + ctx < total - 1: last + ctx else: total - 1

                emit_hunk(kinds, texts, var ia, var jb, s, e, var out)
                first = p
                last = p

        p += 1

    if first >= 0:
        let s = if first - ctx > 0: first - ctx else: 0

        let e = if last + ctx < total - 1: last + ctx else: total - 1

        emit_hunk(kinds, texts, var ia, var jb, s, e, var out)

    if out.length() == 0:
        return 0

    var buf = "--- {name_a}\n+++ {name_b}\n"
    for line in out:
        buf = "{buf}{line}\n"
    stdout().write(buf).get()
    return 0
