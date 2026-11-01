# Dynamic String copy and drop counts: builds each program with MS_COUNT_STR=1 against the counting runtime (`ms-rt` feature
# `stats`, as in tools/leak-check.ms) and prints the totals the program reports at exit, split into static strings (no count to
# change) and owned ones. Owned copies are the allocations unique ownership would add; `bench/tools/copy_report.ms` counts the static
# sites.
# Usage: ms run tools/str-counts.ms -- <ms.toml|file.ms>...
import exe, note, run_program, use_stats_runtime, works from "./lib.ms"
import canonicalize, temporary from "@std/os/fs.ms"
import arguments, set_environment, run from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

export fn main() Int:
    let programs = arguments()

    if programs.length() == 0:
        note("usage: ms run tools/str-counts.ms -- <ms.toml|file.ms>...")
        return 2

    let code = use_stats_runtime()
    if code != 0: return code

    let built = run_program(
        "cargo", ["build", "--release", "--locked", "-q", "-p", "ms-cli"]
    )
    if built != 0: return built

    let ms = canonicalize("target/release/ms{exe()}").get()
    let scratch = temporary("ms-str-counts-").get()
    let binary = "{scratch.path()}/program{exe()}"
    set_environment("MS_COUNT_STR", "1").get()

    for program in programs:
        stdout().write("== {program}\n").get()

        if not works(ms.clone(), ["build", program.clone(), "-o", binary.clone()]):
            note("cannot build {program}")
            return 1

        var text = ""
        if let out = run(binary.clone(), []): text = out.stderr.decode_utf8().get("")

        var found = false

        for line in text.split("\n"):
            if line.contains("ms-rt string"):
                stdout().write(line + "\n").get()
                found = true

        if not found: stdout().write("(no string copies or drops)\n").get()

    return 0
