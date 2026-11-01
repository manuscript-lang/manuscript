# Whole-kernel comparisons against hand-written Go, Rust and (kernels only) C, minimum of N runs (bench/perf/kernels, bench/perf/competence).
# Usage: ms run bench/tools/kernels.ms -- <kernels|competence> [repeats]
# kernels: c-ms is the C a no-GC Manuscript backend would emit; ABLATE=1 adds c-ms builds with one runtime check removed each.
# MS, GO, RUSTC and CC pick the tools.
import ablations, base_versions, c_versions, summarize from "./kernels_table.ms"
import build_go, build_ms, build_rust, capture, env, fail, finish, must, repeats, rotate, sample from "./lib.ms"
import copy_tree, create_directory, temporary from "@std/os/fs.ms"
import arguments from "@std/os/process.ms"

fn build_c(source: String, out: String, flags: List[String]) Result[Unit, Error]:
    var args = ["-O2", "-std=c11", "-ffp-contract=off"].concat(flags)
    args = args.concat([source.clone(), "-o", out.clone()])

    let _ = try must("cc {source}", capture(env("CC", "cc"), args))
    return ok(unit)

fn run(suite: String, n: Int, work: String) Result[String, Error]:
    let here = "bench/perf/{suite}"
    for dir in ["go", "ms", "rust"]:
        try copy_tree("{here}/{dir}", "{work}/{dir}", replace: true)
    for dir in ["rust-checked", "c", "c-ms"]:
        try create_directory("{work}/{dir}")
    try build_go("{work}/go", "{work}/go/bench")
    try build_rust("{work}/rust/main.rs", "{work}/rust/bench", [])
    try build_rust(
        "{work}/rust/main.rs", "{work}/rust-checked/bench", ["-C", "overflow-checks=on"]
    )
    try build_ms("{work}/ms", "{work}/ms/bench")

    var versions = base_versions()

    if suite == "kernels":
        try build_c("{here}/c/plain.c", "{work}/c/bench", [])
        try build_c("{here}/c/ms.c", "{work}/c-ms/bench", [])
        versions = versions.concat(c_versions())

        if env("ABLATE", "0") == "1":
            let flags = [
                ["c-ms-no-poll", "-DMS_NO_POLL"],
                ["c-ms-no-overflow", "-DMS_NO_OVERFLOW"],
                ["c-ms-no-bounds", "-DMS_NO_BOUNDS"],
                [
                    "c-ms-unchecked", "-DMS_NO_POLL -DMS_NO_OVERFLOW -DMS_NO_BOUNDS"
                ]
            ]

            for entry in flags:
                try create_directory("{work}/{entry[0]}")
                try build_c(
                    "{here}/c/ms.c", "{work}/{entry[0]}/bench", entry[1].split(" ")
                )

            versions = versions.concat(ablations())

    var raw = List[String]()

    for i in 0..n:
        # Rotate the order each round so no version always runs first.
        for v in rotate(versions, i):
            let out = try sample("{work}/{v}/bench", [])
            for line in out.split("\n"):
                if line != "": raw.append("{v} {line}")
            raw.append("{v} # end")

    return summarize(raw, suite, n, versions)

export fn main() Int:
    let args = arguments()
    if args.length() == 0 or (args[0] != "kernels" and args[0] != "competence"):
        return fail("usage: kernels.ms -- <kernels|competence> [repeats]")

    var n = 5

    if args.length() > 1:
        if let parsed = repeats(args[1]):
            n = parsed
        else:
            return fail("repeats must be a positive integer")

    let tmp = temporary("{args[0]}-").get()
    return finish(run(args[0], n, tmp.path()))
