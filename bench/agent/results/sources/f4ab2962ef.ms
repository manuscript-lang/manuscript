// ms: allow_effect std.console.read
import stdin, stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Op:
    kind: Int  // 0 unchanged, 1 deletion, 2 insertion
    text: String
    i: Int  // lines of A consumed before this op
    j: Int  // lines of B consumed before this op

fn read_all() List[String]:
    var out = List[String]()
    var s = lines(stdin())
    var more = true

    while more:
        let item = s.next().get()

        if let line = item:
            out.append(line.clone())
        else:
            more = false

    return out

fn next_change(ops: List[Op], begin: Int) Int:
    let total = ops.length()
    var p = begin
    while p < total and ops[p].kind == 0:
        p += 1
    return p

fn span(start: Int, len: Int) String:
    if len == 1:
        return "{start}"

    return "{start},{len}"

export fn main() Int:
    let all = read_all()
    if all.length() == 0:
        return 0

    let header = all[0].split(" ")
    let name_a = header[0]
    let name_b = header[1]
    let ctx = header[2].parse_int().get(0)
    let n = header[3].parse_int().get(0)
    let m = header[4].parse_int().get(0)

    // Full LCS table: tbl[i * w + j] = LCS length of a[i..] and b[j..].
    let w = m + 1
    var tbl = List[Int]()
    for k in 0..(n + 1) * w:
        tbl.append(0)

    var i = n

    while i >= 0:
        var j = m

        while j >= 0:
            if i < n and j < m:
                if all[1 + i] == all[1 + n + j]:
                    tbl[i * w + j] = tbl[(i + 1) * w + j + 1] + 1
                else:
                    let down = tbl[(i + 1) * w + j]
                    let right = tbl[i * w + j + 1]
                    tbl[i * w + j] = if down >= right: down else: right

            j -= 1

        i -= 1

    // Walk the edit script from (0, 0).
    var ops = List[Op]()
    var ci = 0
    var cj = 0

    while (ci < n) or (cj < m):
        if ci < n and cj < m and all[1 + ci] == all[1 + n + cj]:
            ops.append(Op(0, all[1 + ci].clone(), ci, cj))
            ci += 1
            cj += 1
        else if cj == m or (ci < n and tbl[(ci + 1) * w + cj] >= tbl[ci * w + cj + 1]):
            ops.append(Op(1, all[1 + ci].clone(), ci, cj))
            ci += 1
        else:
            ops.append(Op(2, all[1 + n + cj].clone(), ci, cj))
            cj += 1

    // Group changes into hunks and print them.
    let total = ops.length()
    let ctx2 = 2 * ctx
    var sink = stdout()
    var printed = false
    var k = 0

    while k < total:
        if ops[k].kind == 0:
            k += 1
        else:
            let start = k
            var last = k
            var nxt = next_change(ops, last + 1)

            while nxt < total and nxt - last - 1 <= ctx2:
                last = nxt
                nxt = next_change(ops, last + 1)

            var s = start - ctx
            if s < 0:
                s = 0

            var e = last + ctx
            if e > total - 1:
                e = total - 1

            var la = 0
            var lb = 0

            for q in s..e + 1:
                if ops[q].kind != 2:
                    la += 1
                if ops[q].kind != 1:
                    lb += 1

            var sa = ops[s].i
            if la > 0:
                sa += 1

            var sb = ops[s].j
            if lb > 0:
                sb += 1

            if not printed:
                sink.write("--- {name_a}\n+++ {name_b}\n").get()
                printed = true

            sink.write("@@ -{span(sa, la)} +{span(sb, lb)} @@\n").get()

            for q in s..e + 1:
                let op = ops[q]
                var prefix = " "
                if op.kind == 1:
                    prefix = "-"
                if op.kind == 2:
                    prefix = "+"
                sink.write("{prefix}{op.text}\n").get()

            k = e + 1

    sink.flush().get()
    return 0
