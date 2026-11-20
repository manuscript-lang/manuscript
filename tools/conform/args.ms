// Command-line flags shared by the conformance subcommands: `--flag value`,
// `--flag=value`, and switches that take no value. Repeats keep every value, in order.
import (
	max from "@std/math/math.ms",
	working_directory from "@std/os/env.ms",
	stat from "@std/os/fs.ms",
	system_info from "@std/os/system.ms",

	Phase, phase_from_name from "./fixture.ms",
	Filter from "./select.ms",
)

// Flags that take no value.
SWITCHES := [
	"quiet", "no-stable-check", "prune", "only-missing", "help", "strict", "keep"
]

export type Args:
	// Parallel lists: `names[i]` was given the value `values[i]`.
	names: List[String] = []
	values: List[String] = []
	positional: List[String] = []

export fn parse_args(items: List[String]) Result[Args, String]:
	var args = Args()
	var at = 0

	while at < items.length():
		item := items[at]

		if flag := item.cut_prefix("--"):
			if pair := flag.split_once("="):
				args.names.append(pair.before)
				args.values.append(pair.after)
			else if SWITCHES.contains(flag):
				args.names.append(flag.clone())
				args.values.append("")
			else:
				at += 1
				if at >= items.length(): return error(f"--{flag} needs a value")

				args.names.append(flag.clone())
				args.values.append(items[at].clone())
		else:
			args.positional.append(item.clone())

		at += 1

	return ok(args)

fn Args.has(flag: String) Bool:
	return self.names.contains(flag)

// The last value given for `flag`.
fn Args.one(flag: String) String?:
	var found: String? = none
	for at in 0..self.names.length():
		if self.names[at] == flag: found = self.values[at].clone()
	return found

// Every value of a repeatable flag; each may also be comma separated.
fn Args.many(flag: String) List[String]:
	var out = List[String]()

	for at in 0..self.names.length():
		if self.names[at] != flag: continue

		for part in self.values[at].split(","):
			text := part.trim()
			if not text.is_empty(): out.append(text.clone())

	return out

fn Args.number(flag: String) Result[Int?, String]:
	if text := self.one(flag):
		value := text.parse_int().ok_or(f"--{flag}: bad number {text}")?
		return ok(value)

	return ok(none)

// Fixtures are single-threaded compiles and runs: on a 4-core host, 4 jobs finish the
// corpus in half the time of 2 and 8 gain nothing more.
fn Args.jobs() Result[Int, String]:
	if n := self.number("jobs")?: return ok(max(n, 1))
	return ok(max(system_info().cpu_count, 1))

fn Args.filter() Result[Filter, String]:
	var phases = List[Phase]()
	for name in self.many("phase"):
		phases.append(phase_from_name(name).ok_or(f"unknown phase {name}")?)

	var shard_index = 0
	var shard_count = 1

	if spec := self.one("shard"):
		pair := spec.split_once("/").ok_or("--shard wants i/n")?
		shard_index = pair.before.parse_int().ok_or("--shard wants i/n")?
		shard_count = pair.after.parse_int().ok_or("--shard wants i/n")?
		if shard_count <= 0 or shard_index < 0 or shard_index >= shard_count:
			return error("--shard i/n needs 0 <= i < n")

	return ok(
		Filter(
			tags: self.many("tag"),
			exclude_tags: self.many("exclude-tag"),
			phases: phases,
			ids: self.many("id"),
			shard_index: shard_index,
			shard_count: shard_count,
		)
	)

// The corpus directory: `--corpus`, `$MS_CONFORM_CORPUS`, or
// `tests/conformance/fixtures` found by walking up from the working directory.
fn Args.corpus(environment: Map[String, String]) Result[String, String]:
	if path := self.one("corpus"): return ok(path)
	if path := environment.get("MS_CONFORM_CORPUS"): return ok(path.clone())

	var dir = working_directory().map_error(fn e: e.message)?

	while true:
		candidate := dir + "/tests/conformance/fixtures"
		if info := stat(candidate):
			if info.is_directory(): return ok(candidate)

		if cut := dir.rsplit_once("/"):
			if cut.before.is_empty(): break

			dir = cut.before.clone()
		else:
			break

	return error("cannot find tests/conformance/fixtures; pass --corpus")
