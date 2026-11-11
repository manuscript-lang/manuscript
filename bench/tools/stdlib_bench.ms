// Runs the `bench` blocks of bench/perf/stdlib with the ms binary (MS, default
// target/release/ms) and prints the median, min and max ns per operation for each case,
// optionally limited to names containing a prefix. Usage: ms run
// bench/tools/stdlib_bench.ms [-- samples [name-prefix]] With `--table` as the first
// argument it reads an `ms bench --json` document from standard input instead of
// running it.
import (
	arguments from "@std/os/env.ms",

	finish,
	left,
	ms_binary,
	read_stdin,
	repeats,
	right,
	stdlib_bench,
	usage from "./lib.ms",
	Stats, case_labels, read_cases from "./stdlib_results.ms",
)

export fn stdlib_table(output: String) String!:
	cases := try read_cases(output)
	labels := case_labels(cases.map(fn c: c.name.clone()))
	var width = 4

	for c in cases:
		n := labels.get_or(c.name, "").length()
		if n > width: width = n

	var rows = [
		left("case", width) + "  " + right("median ns/op", 12) + "  " + right(
			"min", 10
		) + "  " + right("max", 10)
	]

	for c in cases:
		s := c.stats.get(Stats(0, none, none, 0.0, none, none, none, none))
		rows.append(
			left(labels.get_or(c.name, ""), width) + "  " + right(
				s.median_ns.to_fixed(2), 12
			) + "  " + right(s.min_ns.get(0.0).to_fixed(2), 10) + "  " + right(
				s.max_ns.get(0.0).to_fixed(2), 10
			)
		)

	return ok(rows.join("\n"))

fn main() Int:
	args := arguments()
	if not args.is_empty() and args[0] == "--table": return finish(
		stdlib_table(read_stdin())
	)

	var n = 5

	if not args.is_empty():
		if parsed := repeats(args[0]):
			n = parsed
		else:
			return usage("samples must be a positive integer")

	filter := if args.length() > 1: args[1].clone() else: ""
	output := stdlib_bench(ms_binary(), n, filter)
	if output.is_error(): return finish(output)

	return finish(stdlib_table(output.get("")))
