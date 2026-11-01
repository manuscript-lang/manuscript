# Counts `copy` instructions in the optimized MIR (what gets compiled; MS_EMIT_OPT=1 ms emit) by operand type and by the op that
# defined the copied value. Every copy of a String retains its object today and would allocate if strings became uniquely owned
# values, so this is the budget for that change. Copies of `str` literals are static and free in that model (cap 0); the rest are
# the budget. Set RAW=1 for the unoptimized lowering. Loop membership is not reported.
# Usage: ms run bench/tools/copy_report.ms -- <project ms.toml|file.ms>...   (MS picks the compiler)
import capture, env, finish, ms_binary, must, read_text, right, usage from "./lib.ms"
import temporary from "@std/os/fs.ms"
import arguments, set_environment from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

# The type text of every `%N: type` block parameter on a `b<N>(...)` header line, keyed by `%N`.
fn block_params(line: String, defs: Map[String, String]) Map[String, String]:
    var out = defs.clone()
    let open = line.index_of("(").get(-1)
    let close = line.last_index_of(")").get(-1)
    if open < 0 or close < open: return out

    for part in line.slice(open + 1, close).get("").split(", "):
        let colon = part.index_of(":").get(-1)
        if colon > 0 and part.starts_with("%"): out.add(
            part.slice(0, colon).get(""), "param"
        )

    return out

fn report(mir: String) List[String]:
    var counts = Map[String, Int]()
    var defs = Map[String, String]()

    for line in mir.split("\n"):
        if line.starts_with("fn "):
            defs = Map[String, String]()
        else if line.starts_with("b") and line.contains("("):
            defs = block_params(line, defs)
        else if line.starts_with("  %") and line.contains(" = "):
            let colon = line.index_of(":").get(-1)
            let id = line.slice(2, colon).get("")
            let eq = line.index_of(" = ").get(-1)
            let words = line.slice(eq + 3, line.length()).get("").split(" ")
            let op = words[0].clone()
            defs.add(id.clone(), op.clone())

            if op == "copy":
                let ty = line.slice(colon + 2, line.length()).get("")
                let shown = ty.slice(0, ty.index_of(" = copy").get(ty.length())).get("")

                let src = if words.length() > 1: words[1].clone() else: ""

                let key = "{shown} <- {defs.get(src).get("?")}"
                counts.add(key.clone(), counts.get(key).get(0) + 1)

    # uniq -c | sort -rn: count descending, ties in descending text order.
    var rows = counts.keys().map(fn k: Row(counts.get(k).get(0), k.clone()))
    rows = rows.sorted(
        fn(a: Row, b: Row) Int: if a.count != b.count: b.count - a.count else: b.text.compare(
            a.text
        )
    )
    return rows.map(fn r: right("{r.count}", 7) + " " + r.text)

type Row:
    count: Int
    text: String

export fn main() Int:
    let targets = arguments()
    if targets.length() == 0: return usage(
        "usage: copy_report.ms -- <ms.toml|file.ms>..."
    )

    let tmp = temporary("copy-report-").get()
    let out = "{tmp.path()}/out.mir"
    if env("RAW", "0") != "1": set_environment("MS_EMIT_OPT", "1").get()

    for target in targets:
        let ran = capture(ms_binary(), ["emit", target.clone(), "-o", out.clone()])
        if not ran.ok or ran.code != 0: return finish(must("ms emit {target}", ran))

        stdout().write("== {target}\n").get()
        for row in report(read_text(out)):
            stdout().write(row + "\n").get()

    return 0
