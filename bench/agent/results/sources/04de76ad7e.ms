import {read_line, stdin, stdout} from "@std/io.ms"
import range from "@std/collections.ms"
import {max, min} from "@std/math.ms"

fn next_line() String:
    return read_line(stdin()).get().get("")

fn read_lines(count: Int) List[String]:
    var lines = List[String]()
    for k in range(0, count):
        lines.append(next_line())
    return lines

fn present(length: Int) Int:
    if length > 0:
        return 1

    return 0

fn span(start: Int, length: Int) String:
    if length == 1:
        return "{start}"

    return "{start},{length}"

fn write_all(text: String) Result[Unit, Error]:
    try stdout().write(text)
    return stdout().flush()

export fn main() Int:
    let header = next_line().split(" ")
    let name_a = header.get(0)
    let name_b = header.get(1)
    let context = header.get(2).parse_int().get(0)
    let n = header.get(3).parse_int().get(0)
    let m = header.get(4).parse_int().get(0)
    let a = read_lines(n)
    let b = read_lines(m)

    # table[i * width + j] holds L(i, j); row n and column m are all zero.
    let width = m + 1
    var table = List[Int]()
    for k in range(0, (n + 1) * width):
        table.append(0)

    for i in range(0, n).reversed():
        for j in range(0, m).reversed():
            if a.get(i) == b.get(j):
                table.set(i * width + j, table.get((i + 1) * width + j + 1) + 1)
            else:
                table.set(
                    i * width + j,
                    max(
                        table.get((i + 1) * width + j), table.get(i * width + j + 1)
                    )
                )

    # The edit script: kind is 0 for unchanged, 1 for deletion, 2 for insertion.
    var kinds = List[Int]()
    var texts = List[String]()
    var a_before = List[Int]()
    var b_before = List[Int]()
    var i = 0
    var j = 0

    while i < n or j < m:
        if i < n and j < m and a.get(i) == b.get(j):
            kinds.append(0)
            texts.append(a.get(i))
            a_before.append(i)
            b_before.append(j)
            i += 1
            j += 1
        else:
            var delete = j == m
            if not delete and i < n:
                delete = table.get((i + 1) * width + j) >= table.get(i * width + j + 1)

            if delete:
                kinds.append(1)
                texts.append(a.get(i))
                a_before.append(i)
                b_before.append(j)
                i += 1
            else:
                kinds.append(2)
                texts.append(b.get(j))
                a_before.append(i)
                b_before.append(j)
                j += 1

    # Group the changes into hunks as [start, end] ranges over the script.
    let count = kinds.length()
    var starts = List[Int]()
    var ends = List[Int]()
    var first = -1
    var last = -1

    for k in range(0, count):
        if kinds.get(k) != 0:
            if last < 0:
                first = k
            else if k - last - 1 > 2 * context:
                starts.append(max(first - context, 0))
                ends.append(min(last + context, count - 1))
                first = k

            last = k

    if last >= 0:
        starts.append(max(first - context, 0))
        ends.append(min(last + context, count - 1))

    if starts.is_empty():
        return 0

    var out = List[String]()
    out.append("--- {name_a}")
    out.append("+++ {name_b}")

    for h in range(0, starts.length()):
        let s = starts.get(h)
        let e = ends.get(h)
        var la = 0
        var lb = 0

        for k in range(s, e + 1):
            if kinds.get(k) != 2:
                la += 1
            if kinds.get(k) != 1:
                lb += 1

        let sa = a_before.get(s) + present(la)
        let sb = b_before.get(s) + present(lb)
        out.append("@@ -{span(sa, la)} +{span(sb, lb)} @@")

        for k in range(s, e + 1):
            if kinds.get(k) == 0:
                out.append(" " + texts.get(k))
            else if kinds.get(k) == 1:
                out.append("-" + texts.get(k))
            else:
                out.append("+" + texts.get(k))

    write_all(out.join("\n") + "\n").get()
    return 0
