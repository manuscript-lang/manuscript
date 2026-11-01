# Compares StringBuilder.append against Rust's String::push_str for pieces of 4 B to 8 KiB (microseconds to build about
# 1 MB) and List[Int].append against Vec::push for 10K to 1M items, min of N runs (bench/perf/strappend).
# Usage: ms run bench/tools/strappend.ms [-- repeats]; MS, RUSTC pick tools; RUSTC_LINKER names the linker when PATH has the
# wrong one (Git's `link` shadows MSVC's on Windows runners).
import build_ms, build_rust, env, exe, finish, repeats, sample, usage from "./lib.ms"
import summarize from "./strappend_table.ms"
import copy_tree, temporary from "@std/os/fs.ms"
import arguments from "@std/os/process.ms"

fn run(work: String, n: Int) Result[String, Error]:
    try copy_tree("bench/perf/strappend/ms", "{work}/ms", replace: true)
    try build_ms("{work}/ms", "{work}/ms/bench{exe()}")

    var flags = List[String]()
    let linker = env("RUSTC_LINKER", "")
    if linker != "": flags = ["-C", "linker={linker}"]
    try build_rust("bench/perf/strappend/rust/main.rs", "{work}/rust{exe()}", flags)

    var raw = List[String]()

    for i in 0..n:
        for v in ["ms", "rust"]:
            let path = if v == "ms": "{work}/ms/bench{exe()}" else: "{work}/rust{exe()}"

            for line in (try sample(path, [])).split("\n"):
                if line != "": raw.append("{i} {v} {line}")

    return summarize(raw, n)

export fn main() Int:
    var n = 5
    let args = arguments()

    if args.length() > 0:
        if let parsed = repeats(args[0]):
            n = parsed
        else:
            return usage("repeats must be a positive integer")

    let tmp = temporary("strappend-").get()
    return finish(run(tmp.path(), n))
