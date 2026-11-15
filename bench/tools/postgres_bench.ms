// Query throughput of the Postgres client: the Manuscript package against Go's pgx and
// Rust's tokio-postgres, each running WORKERS connections of QUERIES sequential
// prepared point lookups. Needs a server (packages/postgres/tests/start-postgres.sh)
// and its PG* variables. Usage: MS=./target/release/ms ms run
// bench/tools/postgres_bench.ms -- <samples>
import (
	arguments from "@std/os/env.ms",

	absolute,
	build_go,
	ensure_directory,
	env,
	finish,
	fixed,
	invalid,
	left,
	median,
	ms_binary,
	must,
	now_ns,
	repeats,
	right,
	run_in,
	usage from "./lib.ms",
)

type Program:
	name: String
	exe: String

type Sample:
	seconds: Float
	output: String

// Runs `program` once and returns its seconds and its output line.
fn once(program: Program, dir: String) Sample!:
	start := now_ns()
	out := must(program.name, run_in(dir, program.exe, []))?
	seconds := (now_ns() - start).to_float() / 1000000000.0
	return ok(Sample(seconds, out.trim()))

fn measure(samples: Int) String!:
	root := absolute("bench/perf/postgres")
	ensure_directory("{root}/.build")

	// The program lives in the package project, so `@pg` is the package's own source.
	ran := run_in(
		absolute("packages/postgres"),
		ms_binary(),
		["build", "bench/main.ms", "-o", "{root}/.build/ms"],
	)
	_built_ms := must("ms build packages/postgres/bench", ran)?
	build_go("{root}/go", "{root}/.build/go")?

	cargo := run_in(
		"{root}/rust",
		env("CARGO", "cargo"),
		["build", "--release", "--quiet"],
	)
	_built := must("cargo build", cargo)?
	_setup := must("setup", run_in(root, "{root}/.build/ms", ["setup"]))?
	programs := [
		Program("Manuscript", "{root}/.build/ms"),
		Program("Go pgx", "{root}/.build/go"),
		Program(
			"Rust tokio-postgres",
			"{root}/rust/target/release/postgres-bench",
		),
	]
	var times: List[List[Float]] = [[], [], []]
	var expected = ""

	for round in 0..samples:
		// Rotate the order so no program always runs first.
		for step in 0..programs.length():
			which := (round + step) % programs.length()
			result := once(programs[which], root)?
			if expected == "": expected = result.output.clone()
			if result.output != expected:
				return invalid(
					"{programs[which].name} printed {result.output}, expected {expected}"
				)

			times[which].append(result.seconds)

	workers := env("WORKERS", "4").parse_int().get(4)
	queries := env("QUERIES", "20000").parse_int().get(20000)
	total := (workers * queries).to_float()
	var report = "{expected}; {workers} connections x {queries} lookups, median of {samples}\n"
	report += "{left("program", 22)}{right("seconds", 10)}{right("queries/s", 12)}\n"

	for which in 0..programs.length():
		seconds := median(times[which])
		report += "{left(programs[which].name, 22)}{right(fixed(seconds, 3), 10)}{right(fixed(total / seconds, 0), 12)}\n"

	return ok(report)

fn main() Int:
	args := arguments()
	if args.length() != 1: return usage("usage: postgres_bench.ms -- <samples>")

	count := repeats(args[0])
	if samples := count: return finish(measure(samples))

	return usage("samples must be a positive integer")
