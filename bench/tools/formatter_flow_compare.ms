// Compares formatter binaries, retaining all output-checked paired samples (bench/perf/formatter-flow).
// Usage: ms run bench/tools/formatter_flow_compare.ms -- BEFORE AFTER --out FILE.csv [--samples 10] [--cpu N]
// Harness output is `count,rounds,shape,elapsed_ns,checksum,source_bytes,output_bytes,rss`.
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",

	absolute, fail, invalid, median, options, write_text from "./lib.ms",
	all_ints, rounds_for, run_pinned from "./study.ms",
)

type Case:
	count: Int
	shape: String

fn cases() List[Case]:
	var out = List[Case]()
	for n in [1, 8, 28, 29, 30, 31, 32, 128, 512, 2048]:
		for shape in ["flow", "pipe", "member"]:
			out.append(Case(n, shape.clone()))
	for n in [1, 32, 512]:
		for shape in ["nonempty", "clause", "inline", "unicode", "crlf", "comments"]:
			out.append(Case(n, shape.clone()))
	for n in [1, 100, 1000]:
		out.append(Case(n, "functions"))
	for n in [1, 32, 512, 8192]:
		for shape in ["list-flat", "list-lines"]:
			out.append(Case(n, shape.clone()))
	return out

// elapsed_ns, checksum, source_bytes, output_bytes, rss
fn run_one(binary: String, c: Case, rounds: Int, cpu: String) List[Int]!:
	out := run_pinned(binary, ["{c.count}", "{rounds}", c.shape.clone()], cpu)?
	fields := out.trim().split(",")
	if (
		fields.length() != 8
		or fields[0] != "{c.count}"
		or fields[1] != "{rounds}"
		or fields[2] != c.shape
	):
		return invalid("malformed harness row: {out.trim()}")

	return all_ints(fields.slice(3, 8).get([]))

fn compare(
	before: String,
	after: String,
	out: String,
	samples: Int,
	cpu: String
) Result[Unit, Error]:
	var paths = Map[String, String]()
	paths.add("before", before.clone())
	paths.add("after", after.clone())

	var rows = [
		"count,shape,sample,binary,rounds,elapsed_ns,checksum_per_query,source_bytes,output_bytes,peak_rss_kib,cpu"
	]

	for c in cases():
		var rounds = Map[String, Int]()
		var expected = List[Int]()

		for name in ["before", "after"]:
			first := run_one(paths.get_or(name, ""), c, 1, cpu)?
			identity := [first[1], first[2], first[3]]
			if expected.is_empty(): expected = identity.clone()
			if identity != expected: return invalid(
				"{c.count} {c.shape}: outputs disagree"
			)

			rounds.add(name.clone(), rounds_for(first[0]))

		var observed = Map[String, List[Float]]()
		observed.add("before", List[Float]())
		observed.add("after", List[Float]())

		for s in 0..samples:
			for name in (if s % 2 == 0: ["before", "after"] else: ["after", "before"]):
				r := rounds.get_or(name, 1)
				got := run_one(paths.get_or(name, ""), c, r, cpu)?
				if [got[1], got[2], got[3]] != expected: return invalid(
					"{c.count} {c.shape}: output changed"
				)

				var list = observed.get_or(name, [])
				list.append(got[0].to_float() / r.to_float())
				observed.add(name.clone(), list)
				rows.append(
					"{c.count},{c.shape},{s},{name},{r},{got[0]},{got[1]},{got[2]},{got[3]},{got[4]},{cpu}"
				)

		old := median(observed.get_or("before", []))
		new := median(observed.get_or("after", []))
		(
			stdout()
			.write(
				"{c.count},{c.shape},before={old.to_fixed(0)}ns,after={new.to_fixed(0)}ns,ratio={(new / old).to_fixed(3)}\n"
			)
			.get()
		)

	write_text(out, rows.join("\n") + "\n")
	return ok(unit)

fn main() Int:
	args := arguments()
	if args.length() < 2: return fail(
		"usage: formatter_flow_compare.ms -- BEFORE AFTER --out FILE [--samples N] [--cpu N]"
	)

	parsed := options(
		args.slice(2, args.length()).get([]), ["out", "samples", "cpu"], ["out"]
	)
	if parsed.is_error(): return fail(parsed.err().message)

	opts := parsed.get(Map[String, String]())
	samples := opts.get_or("samples", "10").parse_int().get(0)
	if samples < 5: return fail("--samples must be at least 5")

	result := compare(
		absolute(args[0].clone()), absolute(args[1].clone()), opts.get_or("out", ""),
		samples, opts.get_or("cpu", "")
	)
	if result.is_error(): return fail(result.err().message)

	return 0
