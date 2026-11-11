// Runs already-built programs in alternating pairs, rejecting failed or incomplete
// samples (bench/perf/string-lines, also used by bench/tools/bytes_index_compare.ms).
// Usage: ms run bench/tools/string_lines_compare.ms -- BEFORE AFTER OUTPUT.csv [--pairs
// 7] [--identity-file FILE.json] A program prints CSV
// `case,input_bytes,iterations,elapsed_ns,checksum`; the identity file is
// `{case: [input bytes, iterations, checksum]}`.
import (
	JsonValue, parse from "@std/data/json.ms",
	arguments from "@std/os/env.ms",

	absolute,
	fail,
	finish,
	invalid,
	median,
	options,
	read_text,
	write_text from "./lib.ms",
	all_ints, run_pinned from "./study.ms",
)

export type Identity:
	input_bytes: Int
	iterations: Int
	checksum: Int

// One validated row of a program's CSV.
export type Row:
	name: String
	iterations: Int
	elapsed_ns: Int
	line: String

export fn builtin_identities() Map[String, Identity]:
	var rows = Map[String, Identity]()
	rows.add("empty", Identity(0, 1000000, 0))
	rows.add("tiny", Identity(4, 1000000, 36000000))
	rows.add("short_unterminated", Identity(5, 1000000, 22000000))
	rows.add("empty_lines", Identity(4, 1000000, 68000000))

	for width in [7, 8, 15, 16, 31, 32, 128, 1024, 8192, 65536]:
		count := 1048576 / (width + 1)
		rows.add(
			"lf_{width}",
			Identity((width + 1) * count, 64, (width + 17) * count * 64),
		)

	rows.add("unicode_crlf", Identity(9002 * 128, 64, 9017 * 128 * 64))
	rows.add("no_newline", Identity(1048576, 64, (1048576 + 17) * 64))
	return rows

// Runs `executable` and validates its CSV against `expected`; returns the rows in the
// program's order.
export fn run_rows(
	executable: String,
	expected: Map[String, Identity],
	cpu: String,
) List[Row]!:
	text := run_pinned(executable, [], cpu)?
	lines := text.split("\n").filter(fn l: l.trim() != "")
	if (
		lines.is_empty()
		or lines[0].trim() != "case,input_bytes,iterations,elapsed_ns,checksum"
	):
		return invalid("invalid header from {executable}")

	var seen = Set[String]()
	var rows = List[Row]()

	for line in lines.slice(1, lines.length()).get([]):
		f := line.trim().split(",")
		if f.length() != 5: return invalid("malformed row: {line}")

		name := f[0].clone()
		if seen.contains(name) or not expected.contains(name): return invalid(
			"duplicate or unknown case: {name}"
		)

		nums := all_ints(f.slice(1, 5).get([]))?
		want := expected.get_or(name, Identity(0, 0, 0))
		if (
			nums[0] != want.input_bytes
			or nums[1] != want.iterations
			or nums[3] != want.checksum
			or nums[2] <= 0
		):
			return invalid("invalid sample: {line}")

		seen.add(name.clone())
		rows.append(Row(name.clone(), nums[1], nums[2], line.trim()))

	if seen.length() != expected.length(): return invalid("missing cases")

	return ok(rows)

fn read_identities(path: String) Map[String, Identity]!:
	doc := parse[JsonValue](read_text(path))
	if doc.is_error(): return invalid("identity file is not JSON")

	members := doc.get(JsonValue.Null).as_map().get(Map[String, JsonValue]())
	if members.is_empty(): return invalid(
		"identity file must contain a nonempty object"
	)

	var out = Map[String, Identity]()

	for entry in members.entries():
		items := entry.value.as_list().get([])
		if entry.key == "" or items.length() != 3: return invalid(
			"each identity must have a name and three integers"
		)

		var n = List[Int]()

		for item in items:
			v := item.as_int()
			if v.is_none() or v.get(-1) < 0: return invalid(
				"identities must have nonnegative integers and positive iterations"
			)

			n.append(v.get(0))

		if n[1] == 0: return invalid(
			"identities must have nonnegative integers and positive iterations"
		)

		out.add(entry.key.clone(), Identity(n[0], n[1], n[2]))

	return ok(out)

fn compare(
	before: String,
	after: String,
	output: String,
	pairs: Int,
	expected: Map[String, Identity],
) Result[String, Error]:
	var paths = Map[String, String]()
	paths.add("before", before.clone())
	paths.add("after", after.clone())
	for name in ["before", "after"]:
		_warm := run_rows(paths.get_or(name, ""), expected, "")?

	var csv = ["pair,variant,case,input_bytes,iterations,elapsed_ns,checksum"]
	var per = Map[String, List[Float]]()

	for pair in 0..pairs:
		for variant in (if pair % 2 == 0: ["before", "after"] else: ["after", "before"]):
			for row in run_rows(paths.get_or(variant, ""), expected, "")?:
				csv.append("{pair},{variant},{row.line}")

				key := "{row.name} {variant}"
				var list = per.get_or(key, [])
				list.append(row.elapsed_ns.to_float() / row.iterations.to_float())
				per.add(key.clone(), list)

	write_text(output, csv.join("\n") + "\n")

	var out = [
		"case,before_median_ns,after_median_ns,before_min_ns,before_max_ns,after_min_ns,after_max_ns,speedup"
	]

	for name in expected.keys():
		b := per.get_or("{name} before", [])
		a := per.get_or("{name} after", [])
		bs := b.sorted()
		as := a.sorted()
		out.append(
			"{name},{median(b).to_fixed(1)},{median(a).to_fixed(1)},{bs[0].to_fixed(1)},{bs[bs.length() - 1].to_fixed(1)},{as[0].to_fixed(1)},{as[as.length() - 1].to_fixed(1)},{(median(b) / median(a)).to_fixed(3)}"
		)

	return ok(out.join("\n"))

fn main() Int:
	args := arguments()
	if args.length() < 3: return fail(
		"usage: string_lines_compare.ms -- BEFORE AFTER OUTPUT [--pairs N] [--identity-file FILE]"
	)

	parsed := options(
		args.slice(3, args.length()).get([]),
		["pairs", "identity-file"],
		[],
	)
	if parsed.is_error(): return fail(parsed.err().message)

	opts := parsed.get(Map[String, String]())
	pairs := opts.get_or("pairs", "7").parse_int().get(0)
	if pairs < 1: return fail("--pairs must be positive")

	var expected = builtin_identities()

	if file := opts.get("identity-file"):
		loaded := read_identities(file)
		if loaded.is_error(): return fail(loaded.err().message)

		expected = loaded.get(expected)

	return finish(
		compare(
			absolute(args[0].clone()),
			absolute(args[1].clone()),
			args[2].clone(),
			pairs,
			expected,
		)
	)
