import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"
import {StringBuilder} from "@std/string.ms"

let SAME = 0
let DELETE = 1
let INSERT = 2

type Step:
    kind: Int
    a_before: Int # lines of A consumed before this step
    b_before: Int # lines of B consumed before this step

# t is flat: L(i, j) is at t[i * w + j], with w = b.length() + 1.
fn lcs_table(a: List[String], b: List[String]) List[Int]:
    let w = b.length() + 1
    var t = List[Int]()
    for cell in 0..(a.length() + 1) * w:
        t.append(0)
    for ri in 0..a.length():
        let i = a.length() - 1 - ri
        for rj in 0..b.length():
            let j = b.length() - 1 - rj
            if a[i] == b[j]:
                t[i * w + j] = t[(i + 1) * w + j + 1] + 1
            else if t[(i + 1) * w + j] >= t[i * w + j + 1]:
                t[i * w + j] = t[(i + 1) * w + j]
            else:
                t[i * w + j] = t[i * w + j + 1]
    return t

fn edit_script(a: List[String], b: List[String]) List[Step]:
    let t = lcs_table(a, b)
    let w = b.length() + 1
    var steps = List[Step]()
    var i = 0
    var j = 0
    while i < a.length() or j < b.length():
        if i < a.length() and j < b.length() and a[i] == b[j]:
            steps.append(Step(SAME, i, j))
            i += 1
            j += 1
        else if j == b.length() or (i < a.length() and t[(i + 1) * w + j] >= t[i * w + j + 1]):
            steps.append(Step(DELETE, i, j))
            i += 1
        else:
            steps.append(Step(INSERT, i, j))
            j += 1
    return steps

fn range_text(before: Int, len: Int) String:
    let start = if len > 0: before + 1 else: before
    if len == 1: return "{start}"
    return "{start},{len}"

fn write_hunk(var out: StringBuilder, steps: List[Step], a: List[String], b: List[String], first: Int, last: Int, context: Int) Unit:
    let s =if first > context: first - context else: 0
    let e = if last + context < steps.length(): last + context else: steps.length() - 1
    var la = 0
    var lb = 0
    for k in s..(e + 1):
        if steps[k].kind != INSERT:
            la += 1
        if steps[k].kind != DELETE:
            lb += 1
    out.append("@@ -{range_text(steps[s].a_before, la)} +{range_text(steps[s].b_before, lb)} @@\n")
    for k in s..(e + 1):
        let step = steps[k]
        if step.kind == SAME:
            out.append(" {a[step.a_before]}\n")
        else if step.kind == DELETE:
            out.append("-{a[step.a_before]}\n")
        else:
            out.append("+{b[step.b_before]}\n")

export fn main() Int:
    let lines = read_lines(stdin()).get()
    let head = lines[0].split(" ")
    let context = head[2].parse_int().get(0)
    let n = head[3].parse_int().get(0)
    let m = head[4].parse_int().get(0)
    var a = List[String]()
    var b = List[String]()
    for k in 0..n:
        a.append(lines[1 + k].clone())
    for k in 0..m:
        b.append(lines[1 + n + k].clone())
    let steps = edit_script(a, b)
    var changes = List[Int]()
    for k in 0..steps.length():
        if steps[k].kind != SAME:
            changes.append(k)
    if changes.length() == 0:
        return 0
    var out = StringBuilder()
    out.append("--- {head[0]}\n")
    out.append("+++ {head[1]}\n")
    var first = 0
    var last = 0
    first = changes[0]
    last = changes[0]
    for c in 1..changes.length():
        if changes[c] - last - 1 <= 2 * context:
            last = changes[c]
        else:
            write_hunk(var out, steps, a, b, first, last, context)
            first = changes[c]
            last = changes[c]
    write_hunk(var out, steps, a, b, first, last, context)
    stdout().write(out.build()).get()
    return 0
