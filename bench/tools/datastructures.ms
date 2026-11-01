# Core data-structure operations in Manuscript, Go and Rust (ns per operation, best of N) (bench/perf/datastructures).
# Usage: ms run bench/tools/datastructures.ms [-- repeats]; MS picks the Manuscript compiler.
import (
    build_go,
    build_ms,
    build_rust,
    finish,
    repeats,
    rotate,
    sample,
    usage
) from "./lib.ms"
import summarize from "./datastructures_table.ms"
import copy_tree, temporary from "@std/os/fs.ms"
import arguments from "@std/os/process.ms"

fn run(work: String, n: Int) Result[String, Error]:
    let here = "bench/perf/datastructures"
    for dir in ["go", "ms"]:
        try copy_tree("{here}/{dir}", "{work}/{dir}", replace: true)
    try build_ms("{work}/ms", "{work}/ms/bench")
    try build_go("{work}/go", "{work}/go/bench")
    try build_rust("{here}/rust/main.rs", "{work}/rs", [])

    var raw = List[String]()

    for i in 0..n:
        for v in rotate(["ms", "go", "rs"], i):
            let exe = if v == "rs": "{work}/rs" else: "{work}/{v}/bench"
            for line in (try sample(exe, [])).split("\n"):
                if line != "": raw.append("{v} {line}")
            raw.append("{v} # end")

    return summarize(raw, n)

export fn main() Int:
    var n = 5
    let args = arguments()

    if args.length() > 0:
        if let parsed = repeats(args[0]):
            n = parsed
        else:
            return usage("repeats must be a positive integer")

    let tmp = temporary("datastructures-").get()
    return finish(run(tmp.path(), n))
