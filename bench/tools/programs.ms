# Compares Manuscript, Go and Rust on small whole programs (bench/perf/programs).
# Usage: ms run bench/tools/programs.ms [-- repeats]; MS, GO, RUSTC pick tools; BENCH_OUTPUT keeps binaries, input and raw samples.
import absolute, build_go, build_ms, build_rust, env, fail, finish, repeats, sample from "./lib.ms"
import summarize from "./programs_table.ms"
import copy_tree, create_directory, temporary, write_file from "@std/fs.ms"
import arguments from "@std/process.ms"

fn orders() List[List[String]]:
    return [
        ["go", "ms", "rust", "rust-checked"], ["ms", "rust-checked", "go", "rust"],
        ["rust-checked", "rust", "ms", "go"], ["rust", "go", "rust-checked", "ms"]
    ]

fn run(work: String, n: Int) Result[String, Error]:
    let here = "bench/perf/programs"
    for dir in ["go", "ms", "rust"]:
        try copy_tree("{here}/{dir}", "{work}/{dir}", replace: true)
    try create_directory("{work}/rust-checked")

    var input = List[String]()
    for i in 0..200000:
        input.append("2026-03-01T00:00:00Z 10.1.2.3 GET /api/users/{i} 200\n")

    let lines = input.join("")
    try write_file("{work}/lines.txt", lines, replace: true)
    try build_go("{work}/go", "{work}/go/bench")
    try build_rust("{work}/rust/main.rs", "{work}/rust/bench", [])
    try build_rust(
        "{work}/rust/main.rs", "{work}/rust-checked/bench", ["-C", "overflow-checks=on"]
    )
    try build_ms("{work}/ms", "{work}/ms/bench")

    var raw = List[String]()

    for i in 0..n:
        for v in orders()[i % 4]:
            let out = try sample("{work}/{v}/bench", [], lines)
            for line in out.split("\n"):
                if line != "": raw.append("{v} {line}")

    return summarize(raw, n)

export fn main() Int:
    var n = 7
    let args = arguments()

    if args.length() > 0:
        if let parsed = repeats(args[0]):
            n = parsed
        else:
            return fail("repeats must be a positive integer")

    let keep = env("BENCH_OUTPUT", "")

    if keep != "":
        create_directory(keep, recursive: true).get()
        return finish(run(absolute(keep), n))

    let tmp = temporary("programs-").get()
    return finish(run(tmp.path(), n))
