// Compares two already-built revisions against shared handwritten Go samples. Usage: ms
// run bench/tools/programs_compare.ms -- --before B --after A --go G --input I --output
// DIR [--repeats 30]
import (
	arguments from "@std/os/env.ms",

	absolute,
	ensure_directory,
	fail,
	finish,
	options,
	permutations,
	read_text,
	sample,
	write_text from "./lib.ms",
	summarize from "./programs_table.ms",
)

fn lines_of(version: String, content: String) List[String]:
	return content.split("\n").filter(fn l: l != "").map(fn l: "{version} {l}")

fn run(opts: Map[String, String], n: Int) Result[String, Error]:
	names := ["go", "before", "after"]
	var programs = Map[String, String]()
	for name in names:
		programs.add(name.clone(), absolute(opts.get_or(name, "")))

	orders := permutations(names)
	input := read_text(opts.get_or("input", ""))
	var raw = Map[String, List[String]]()
	raw.add("before", List[String]())
	raw.add("after", List[String]())

	for i in 0..n:
		var results = Map[String, String]()
		for version in orders[i % orders.length()]:
			results.add(
				version.clone(),
				try sample(programs.get_or(version, ""), [], input),
			)

		for revision in ["before", "after"]:
			var lines = raw.get_or(revision, [])
			lines = lines.concat(lines_of("go", results.get_or("go", "")))
			lines = lines.concat(lines_of("ms", results.get_or(revision, "")))
			raw.add(revision.clone(), lines)

	out := opts.get_or("output", "")
	ensure_directory(out)

	var report = List[String]()

	for revision in ["before", "after"]:
		lines := raw.get_or(revision, [])
		write_text("{out}/programs-{revision}.txt", lines.map(fn l: l + "\n").join(""))

		table := try summarize(lines, n)
		write_text("{out}/programs-{revision}.md", table + "\n")
		report.append("{revision}\n{table}")

	return ok(report.join("\n"))

fn main() Int:
	parsed := options(
		arguments(),
		["before", "after", "go", "input", "output", "repeats"],
		["before", "after", "go", "input", "output"],
	)
	if parsed.is_error(): return fail(parsed.err().message)

	opts := parsed.get(Map[String, String]())
	n := opts.get_or("repeats", "30").parse_int().get(0)
	if n < 1: return fail("repeats must be positive")

	return finish(run(opts, n))
