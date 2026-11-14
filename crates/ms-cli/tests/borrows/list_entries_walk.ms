import stdout from "@std/io/io.ms"

type Row:
    name: String
    n: Int

fn show(e: ListEntry[String]) String:
    return "{e.index}={e.value}"

fn main() Unit:
    names := ["a", "bb", "ccc"]
    rows := [Row(name: "x", n: 1), Row(name: "y", n: 2)]
    var out = ""
    for e in names.entries():
        if e.index == 1:
            continue
        out += "{e.index}:{e.value.length()} "
    for e in rows.entries():
        out += "{e.value.name}{e.value.n + e.index} "
    for e in names.entries():
        if e.index == 2:
            break
        out += show(e) + " "
    for e in [10, 20, 30].entries():
        for f in names.entries():
            out += "{e.value + f.index} "
    fns := names.entries().map(fn e: e.index + e.value.length())
    _ := stdout().write("{out}{fns}\n")
