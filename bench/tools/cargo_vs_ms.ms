# Compares an `@std` parser with the same Rust crate on the same generated document: runs the Manuscript program and then
# the Rust one, each printing its own timing.
# Usage: ms run bench/tools/cargo_vs_ms.ms -- <toml|csv>   (MS picks the compiler)
import ms_binary, run_inherit, usage from "./lib.ms"
import arguments from "@std/process.ms"

export fn main() Int:
    let args = arguments()
    if args.length() != 1 or (args[0] != "toml" and args[0] != "csv"):
        return usage("usage: cargo_vs_ms.ms -- <toml|csv>")

    let dir = "bench/perf/{args[0]}"
    let first = run_inherit("{dir}/ms", ms_binary(), ["run", "src/main.ms"])
    if first != 0: return first

    return run_inherit("{dir}/rust", "cargo", ["run", "--release", "--quiet"])
