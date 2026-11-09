// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
import stdin, stdout from "@std/io/io.ms"
import lines, collect from "@std/io/streams.ms"

fn range_text(start: Int, len: Int) String:
    if len == 1: return "{start}"
    return "{start},{len}"

export fn main() Int:
    let rows = collect(lines(stdin())).get()
    let head = rows[0].split(" ")
    let name_a = head[0]
    let name_b = head[1]
    let ctx = head[2].parse_int().get(0)
    let n = head[3].parse_int().get(0)
    let m = head[4].parse_int().get(0)
    let w = m + 1

    // LCS suffix table: L[i][j] = LCS length of a[i..] and b[j..].
    var table = List[Int]()
    for _k in 0..(n + 1) * w:
        table.append(0)
    var i = n - 1
    while i >= 0:
        var j = m - 1
        while j >= 0:
            if rows[1 + i] == rows[1 + n + j]:
                table[i * w + j] = table[(i + 1) * w + j + 1] + 1
            else:
                let down = table[(i + 1) * w + j]
                let right = table[i * w + j + 1]
                table[i * w + j] = if down >= right: down else: right
            j -= 1
        i -= 1

    // Edit script: kind 0 = equal, 1 = delete a[ai], 2 = insert b[bj].
    // ai/bj hold the walk position before each op.
    var kinds = List[Int]()
    var ais = List[Int]()
    var bjs = List[Int]()
    var pi = 0
    var pj = 0
    while pi < n or pj < m:
        if pi < n and pj < m and rows[1 + pi] == rows[1 + n + pj]:
            kinds.append(0)
            ais.append(pi)
            bjs.append(pj)
            pi += 1
            pj += 1
        else if pj == m or (pi < n and table[(pi + 1) * w + pj] >= table[pi * w + pj + 1]):
            kinds.append(1)
            ais.append(pi)
            bjs.append(pj)
            pi += 1
        else:
            kinds.append(2)
            ais.append(pi)
            bjs.append(pj)
            pj += 1

    let total = kinds.length()
    var out = ""
    var header_done = false
    var k = 0
    while k < total:
        if kinds[k] == 0:
            k += 1
            continue
        // Group consecutive changes whose unchanged gap is at most 2 * ctx.
        let gs = k
        var ge = k
        var scan = k + 1
        while scan < total:
            if kinds[scan] != 0:
                if scan - ge - 1 <= 2 * ctx:
                    ge = scan
                else:
                    break
            scan += 1
        let lo = if gs - ctx > 0: gs - ctx else: 0
        let hi = if ge + ctx < total - 1: ge + ctx else: total - 1

        var la = 0
        var lb = 0
        var body = ""
        for t in lo..hi + 1:
            if kinds[t] == 0:
                la += 1
                lb += 1
                body = body + " " + rows[1 + ais[t]] + "\n"
            else if kinds[t] == 1:
                la += 1
                body = body + "-" + rows[1 + ais[t]] + "\n"
            else:
                lb += 1
                body = body + "+" + rows[1 + n + bjs[t]] + "\n"

        let sa = ais[lo] + (if la > 0: 1 else: 0)
        let sb = bjs[lo] + (if lb > 0: 1 else: 0)
        if not header_done:
            out = out + "--- " + name_a + "\n+++ " + name_b + "\n"
            header_done = true
        out = out + "@@ -" + range_text(sa, la) + " +" + range_text(sb, lb) + " @@\n" + body
        k = ge + 1

    if header_done:
        stdout().write(out).get()
    return 0
