import (
    lines from "@std/io/streams.ms",
    stdin from "@std/io/io.ms",
)

// ms: allow_effect std.console.read
// Reads every line of standard input, without terminators.
fn read_input() List[String]!:
    var out = List[String]()
    for line in lines(stdin()):
        out.append(line)
    return ok(out)

// Renders a hunk range: `start`, or `start,len` unless len is exactly 1.
fn range_text(start: Int, len: Int) String:
    if len == 1:
        return "{start}"

    return "{start},{len}"

export fn main() Int:
    var input = read_input().get()
    if input.length() == 0:
        return 0

    let head = input[0].split(" ")
    let ctx = head[2].parse_int().get(0)
    let n = head[3].parse_int().get(0)
    let m = head[4].parse_int().get(0)

    // A lines are input[1 + i], B lines are input[1 + n + j].
    // Missing trailing lines count as empty lines.
    while input.length() < 1 + n + m:
        input.append("")

    // tab[i * w + j] = LCS length of a[i..] and b[j..]
    let w = m + 1
    var tab = List[Int]()
    for k in 0..(n + 1) * w:
        tab.append(0)

    for di in 0..n:
        let i = n - 1 - di

        for dj in 0..m:
            let j = m - 1 - dj

            if input[1 + i] == input[1 + n + j]:
                tab[i * w + j] = tab[(i + 1) * w + j + 1] + 1
            else:
                let down = tab[(i + 1) * w + j]
                let right = tab[i * w + j + 1]

                if down >= right:
                    tab[i * w + j] = down
                else:
                    tab[i * w + j] = right

    // Edit script: kind 0 = unchanged, 1 = deletion, 2 = insertion.
    // refs holds the index into input of the line's text.
    var kinds = List[Int]()
    var refs = List[Int]()
    var i = 0
    var j = 0

    while i < n or j < m:
        if i < n and j < m and input[1 + i] == input[1 + n + j]:
            kinds.append(0)
            refs.append(1 + i)
            i += 1
            j += 1
        else:
            var drop_a = false

            if j == m:
                drop_a = true
            else if i < n:
                if tab[(i + 1) * w + j] >= tab[i * w + j + 1]:
                    drop_a = true

            if drop_a:
                kinds.append(1)
                refs.append(1 + i)
                i += 1
            else:
                kinds.append(2)
                refs.append(1 + n + j)
                j += 1

    let s = kinds.length()
    var has_change = false
    for q in 0..s:
        if kinds[q] != 0:
            has_change = true
    if not has_change:
        return 0

    // dist[q] = script distance from op q to the nearest change.
    var dist = List[Int]()
    for q in 0..s:
        dist.append(1000000000)

    var last = -1000000000

    for q in 0..s:
        if kinds[q] != 0:
            last = q
        if q - last < dist[q]:
            dist[q] = q - last

    var nxt = 1000000000

    for dd in 0..s:
        let q = s - 1 - dd
        if kinds[q] != 0:
            nxt = q
        if nxt - q < dist[q]:
            dist[q] = nxt - q

    var out = List[String]()
    out.append("--- {head[0]}")
    out.append("+++ {head[1]}")

    var p = 0
    var ca = 0
    var cb = 0

    while p < s:
        if kinds[p] != 0 or dist[p] <= ctx:
            var e = p
            while e < s and (kinds[e] != 0 or dist[e] <= ctx):
                e += 1

            var la = 0
            var lb = 0

            for q in p..e:
                if kinds[q] != 2:
                    la += 1
                if kinds[q] != 1:
                    lb += 1

            var sa = ca
            if la > 0:
                sa = ca + 1

            var sb = cb
            if lb > 0:
                sb = cb + 1

            let ra = range_text(sa, la)
            let rb = range_text(sb, lb)
            out.append("@@ -{ra} +{rb} @@")

            for q in p..e:
                let t = input[refs[q]]

                if kinds[q] == 0:
                    out.append(" {t}")
                else if kinds[q] == 1:
                    out.append("-{t}")
                else:
                    out.append("+{t}")

            for q in p..e:
                if kinds[q] != 2:
                    ca += 1
                if kinds[q] != 1:
                    cb += 1

            p = e
        else:
            ca += 1
            cb += 1
            p += 1

    for line in out:
        print(line)
    return 0
