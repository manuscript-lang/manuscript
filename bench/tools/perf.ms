// ms: allow_effect std.env.read
// ms: allow_effect std.env.write
// ms: allow_effect std.fs.read
// ms: allow_effect std.process.run
// ms: allow_effect std.console.write

// The one runner of the performance suite (bench/perf/groups.txt). Usage, from the
// repository root, with MS naming the ms to measure (default
// .artifacts/build/release/src/cli/ms):
//   ms run bench/tools/perf.ms -- list                    every group, its kind, command and results page
//   ms run bench/tools/perf.ms -- run <group|time|count|all> [samples]   run groups (default 5 samples)
//   ms run bench/tools/perf.ms -- check                   the index is complete and its pages exist
// `make perf-list`, `make perf GROUP=<name> SAMPLES=<n>` and `make perf-check` call these.
// A `probe` group has no single command: its page holds the protocol.
import (
	arguments, set_environment from "@std/os/env.ms",
	list from "@std/os/fs.ms",

	exists,
	fail,
	invalid,
	ms_binary,
	note,
	read_text,
	repeats,
	run_inherit,
	usage from "./lib.ms",
	Group, argv, layout_problems, parse_groups from "./perf_groups.ms",
)

PERF := "bench/perf"

fn load() List[Group]! {
	return parse_groups(read_text(f"{PERF}/groups.txt"))
}

fn show(groups List[Group]) Int {
	for g in groups {
		results := if g.results == "" { "-" } else { g.results.clone() }
		note(f"{g.name} [{g.kind}] {results}")
		note(
			f"    {if g.command == "" { "see the results page" } else { g.command.clone() }}"
		)
	}

	return 0
}

fn select(groups List[Group], names List[String]) List[Group]! {
	var picked = List[Group]()

	for name in names {
		var found = false

		for g in groups {
			if g.name == name or name == "all" or (name == g.kind and name != "probe") {
				if g.command != "" { picked.append(g.clone()) }
				found = true
			}
		}

		if not found { return invalid(f"unknown group {name}") }
	}

	return ok(picked)
}

fn run_groups(groups List[Group], names List[String], samples Int) Int {
	var picked = List[Group]()

	if found := select(groups, names) {
		picked = found
	} else {
		return fail("unknown group; `list` shows the names")
	}

	if picked.is_empty() { return fail("nothing to run: a probe group has no command") }

	binary := ms_binary()
	void set_environment("MS", binary.clone())

	var status = 0

	for g in picked {
		note(f"== {g.name}")

		words := argv(g, binary, samples)
		code := run_inherit(".", words[0].clone(), words.drop(1))

		if code != 0 {
			note(f"{g.name} exited {code}")
			status = code
		}
	}

	return status
}

fn check(groups List[Group]) Int {
	entries := list(PERF).get_or([]).map(e => e.name.clone())
	investigations := read_text(f"{PERF}/investigations.txt").split("\n").filter(
		l => l.trim() != "" and not l.starts_with("#")
	)
	var problems = layout_problems(groups, investigations, entries)
	readme := read_text(f"{PERF}/README.md")

	for g in groups {
		if g.results != "" and not exists(f"{PERF}/{g.results}") {
			problems.append(f"{g.name}: results page {g.results} is missing")
		}
		if not readme.contains(f"`{g.name}`") {
			problems.append(f"{g.name}: not named in bench/perf/README.md")
		}
	}

	for p in problems { note(p) }
	return if problems.is_empty() { 0 } else { 1 }
}

fn main() Int {
	args := arguments()
	if args.is_empty() { return usage("usage: perf.ms -- <list|run|check> ...") }

	var groups = List[Group]()

	if loaded := load() {
		groups = loaded
	} else {
		return fail("bench/perf/groups.txt is invalid")
	}

	if args[0] == "list" { return show(groups) }
	if args[0] == "check" { return check(groups) }
	if args[0] != "run" or args.length() < 2 {
		return usage("usage: perf.ms -- run <group|time|count|all> [samples]")
	}

	var samples = 5
	var names = [args[1].clone()]

	if args.length() > 2 {
		if parsed := repeats(args[2]) {
			samples = parsed
		} else {
			return fail("samples must be a positive integer")
		}
	}

	return run_groups(groups, names, samples)
}
