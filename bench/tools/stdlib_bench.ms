# Runs the `bench` blocks of bench/perf/stdlib with the ms binary (MS, default target/release/ms) and prints the median, min and
# max ns per operation for each case, optionally limited to names containing a prefix.
# Usage: ms run bench/tools/stdlib_bench.ms [-- samples [name-prefix]]
# With `--table` as the first argument it reads an `ms bench --json` document from standard input instead of running it.
import Invalid, finish, ms_binary, left, read_stdin, repeats, right, stdlib_bench, usage from "./lib.ms"
import Stats, case_labels, read_cases from "./stdlib_results.ms"
import arguments from "@std/os/process.ms"

export fn stdlib_table(output: String) Result[String, Invalid]:
    let cases = try read_cases(output)
    let labels = case_labels(cases.map(fn c: c.name.clone()))
    var width = 4

    for c in cases:
        let n = labels.get(c.name).get("").length()
        if n > width: width = n

    var rows = [
        left("case", width) + "  " + right("median ns/op", 12) + "  " + right(
            "min", 10
        ) + "  " + right("max", 10)
    ]

    for c in cases:
        let s = c.stats.get(Stats(0, none, none, 0.0, none, none, none, none))
        rows.append(
            left(labels.get(c.name).get(""), width) + "  " + right(
                s.median_ns.to_fixed(2), 12
            ) + "  " + right(s.min_ns.get(0.0).to_fixed(2), 10) + "  " + right(
                s.max_ns.get(0.0).to_fixed(2), 10
            )
        )

    return ok(rows.join("\n"))

export fn main() Int:
    let args = arguments()
    if args.length() > 0 and args[0] == "--table": return finish(
        stdlib_table(read_stdin())
    )

    var n = 5

    if args.length() > 0:
        if let parsed = repeats(args[0]):
            n = parsed
        else:
            return usage("samples must be a positive integer")

    let filter = if args.length() > 1: args[1].clone() else: ""

    let output = stdlib_bench(ms_binary(), n, filter)
    if output.is_error(): return finish(output)

    return finish(stdlib_table(output.get("")))
