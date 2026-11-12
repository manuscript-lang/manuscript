// Engineering-task benchmark against C, portable across Linux, macOS and Windows
// (bench/perf/engineering). Builds each stdin task in Manuscript and C, feeds both the
// generated input, requires identical output, and prints the minimum wall time in ms.
// Usage: ms run bench/tools/engineering.ms -- [samples] [scale]
// MS picks the compiler, CC the C compiler (default cc), BENCH_OUTPUT keeps the files.
import (
	arguments from "@std/os/env.ms",
	temporary from "@std/os/fs.ms",

	absolute,
	capture,
	ensure_directory,
	env,
	exe,
	finish,
	invalid,
	left,
	must,
	ms_binary,
	now_ns,
	platform,
	read_text,
	repeats,
	right,
	sample,
	usage from "./lib.ms",
)

type Task:
	name: String
	input: String

fn tasks() List[Task]:
	return [
		Task("logstats", "access.log"),
		Task("csvgroup", "orders.csv"),
		Task("wordfreq", "words.txt"),
		Task("sortrecords", "records.txt"),
		Task("grep", "access.log"),
		Task("jsonsum", "records.json"),
		Task("dedupe", "records.txt"),
		Task("report", "records.txt"),
	]

fn best(samples: List[Int]) Float:
	var low = samples[0]
	for s in samples:
		if s < low: low = s
	return low.to_float() / 1000000.0

fn timed(app: String, input: String) Int!:
	start := now_ns()
	_out := sample(app, [], input)?
	return ok(now_ns() - start)

fn run_task(here: String, work: String, t: Task, n: Int) String!:
	ms_app := "{work}/{t.name}_ms{exe()}"
	c_app := "{work}/{t.name}_c{exe()}"
	_b := must(
		"ms build {t.name}",
		capture(ms_binary(), ["build", "{here}/ms/{t.name}.ms", "-o", ms_app.clone()]),
	)?
	_c := must(
		"cc {t.name}",
		capture(env("CC", "cc"), ["-O2", "-o", c_app.clone(), "{here}/c/{t.name}.c"]),
	)?

	input := read_text("{work}/input/{t.input}")
	expected := sample(c_app, [], input)?
	if sample(ms_app, [], input)? != expected: return invalid("{t.name}: ms output differs from C")

	var ms_ns = List[Int]()
	var c_ns = List[Int]()
	for round in 0..n:
		c_ns.append(timed(c_app, input)?)
		ms_ns.append(timed(ms_app, input)?)

	m := best(ms_ns)
	c := best(c_ns)
	return ok(
		left(t.name, 12) + " " + right(m.to_fixed(1), 9) + " " + right(c.to_fixed(1), 9)
		+ " " + right((m / c).to_fixed(2), 7) + "x"
	)

fn run(work: String, n: Int, scale: String) String!:
	here := absolute("bench/perf/engineering")
	_g := must(
		"gen",
		capture(ms_binary(), ["run", "{here}/gen.ms", "--", "{work}/input", scale]),
	)?
	var rows = ["{platform()} ms/c, min of {n}", left("task", 12) + " " + right("ms ms", 9) + " " + right("c ms", 9) + " " + right("ms/c", 8)]
	for t in tasks():
		rows.append(run_task(here, work, t, n)?)
	return ok(rows.join("\n") + "\n")

fn main() Int:
	var n = 5
	args := arguments()
	if not args.is_empty():
		if parsed := repeats(args[0]):
			n = parsed
		else:
			return usage("samples must be a positive integer")
	scale := if args.length() > 1: args[1].clone() else: "1"

	keep := env("BENCH_OUTPUT", "")
	if keep != "":
		ensure_directory(keep)
		return finish(run(absolute(keep), n, scale))

	tmp := temporary("engineering-").get()
	return finish(run(tmp.path(), n, scale))
