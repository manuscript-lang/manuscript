// The commands that run an `ms` binary on the corpus: `run`, `record` and `diff`.
import (
	stderr from "@std/io/io.ms",
	working_directory from "@std/os/env.ms",
	create_directory, stat, temporary_directory, write_file from "@std/os/fs.ms",

	Args from "./args.ms",
	Discovered, Fixture, discover from "./fixture.ms",
	pretty_line from "./json_util.ms",
	Ctx from "./observe.ms",
	RecordOptions, diff_binaries, record from "./record.ms",
	has_regressions,
	has_unexpected_pass,
	summary_lines,
	to_json,
	to_markdown from "./report.ms",
	Case, Outcome, run_all from "./runner.ms",
	ExpectFail, Filter, load_expect_fail, select from "./select.ms",
)

fn note(message: String) Void:
	void stderr().write(f"{message}\n")

// `path` made absolute when it has directory components (bare names stay for PATH lookup).
fn absolute(path: String) String:
	if path.starts_with("/") or not path.contains("/"): return path.clone()
	if cwd := working_directory(): return f"{cwd}/{path}"

	return path.clone()

// The `ms` binary: `flag`, `$MS`, `./ms`, or `ms` on PATH.
fn binary(args: Args, flag: String, environment: Map[String, String]) String:
	if path := args.one(flag): return absolute(path)
	if path := environment.get("MS"): return absolute(path.clone())
	if stat("./ms").is_ok(): return absolute("./ms")

	return "ms"

// The settings of one side of a comparison: `flag` is `ms`, `a` or `b`.
fn context(
	args: Args,
	flag: String,
	environment: Map[String, String],
) Result[Ctx, String]:
	scratch := temporary_directory("ms-conform-*").map_error(fn e: e.message)?
	var ctx = Ctx(ms: binary(args, flag, environment), scratch: scratch)
	ctx.leaks = environment.contains("CONFORM_LEAKS")
	ctx.build_type = environment.get_or("CONFORM_BUILD_TYPE", "Release")
	if scale := args.one("timeout-scale"):
		ctx.timeout_scale = (
			scale
			.parse_float()
			.ok_or(f"--timeout-scale: bad number {scale}")?
		)

	for pair in args.many(f"env-{flag}"):
		parts := (
			pair
			.split_once("=")
			.ok_or(f"--env-{flag} wants KEY=VALUE, got `{pair}`")?
		)
		ctx.env.add(parts.before, parts.after)

	return ok(ctx)

// Every fixture under the corpus, warnings to stderr; an empty corpus is an error.
fn load(args: Args, environment: Map[String, String]) Result[Discovered, String]:
	corpus := args.corpus(environment)?
	found := discover(corpus)
	for warning in found.warnings:
		note(f"warning: {warning}")
	if found.fixtures.is_empty(): return error(f"no fixtures under {corpus}")

	return ok(found)

fn pick(all: List[Fixture], filter: Filter) List[Fixture]:
	var chosen = List[Fixture]()
	for at in select(all, filter):
		chosen.append(all[at].clone())
	return chosen

fn write_text(path: String, content: String) Result[Void, String]:
	if parts := path.rsplit_once("/"):
		if not parts.before.is_empty(): void create_directory(
			parts.before,
			recursive: true,
		)
	write_file(path, content, replace: true).wait().map_error(
		fn e: f"{path}: {e.message}"
	)?
	return ok(void)

fn print_lines(lines: List[String]) Void:
	for line in lines:
		print(line)

fn write_reports(args: Args, label: String, cases: List[Case]) Result[Void, String]:
	max_failures := args.number("max-failures")?.get_or(100)
	if path := args.one("json"): write_text(path, pretty_line(to_json(label, cases)))?
	if path := args.one("markdown"): write_text(
		path,
		to_markdown(label, cases, max_failures),
	)?
	return ok(void)

// Runs the corpus against `--ms` and compares with the recorded expectations.
export fn run_command(args: Args, environment: Map[String, String]) Result[Int, String]:
	found := load(args, environment)?
	chosen := pick(found.fixtures, args.filter()?)
	ctx := context(args, "ms", environment)?
	var allow = ExpectFail()
	if path := args.one("expect-fail"): allow = load_expect_fail(path)?
	note(
		f"running {chosen.length()} of {found.fixtures.length()} fixtures with {ctx.ms}"
	)

	cases := run_all(ctx, chosen, allow, args.jobs()?)
	print_lines(summary_lines(cases))
	write_reports(args, ctx.ms, cases)?

	if path := args.one("write-expect-fail"):
		var content = "# Known failures; remove entries as they are fixed.\n"
		for item in cases:
			if item.outcome != Outcome.Pass and item.outcome != Outcome.UnexpectedPass:
				content += f"{item.id}\n"
		write_text(path, content)?

	strict_fail := args.has("strict") and has_unexpected_pass(cases)
	return ok(if has_regressions(cases) or strict_fail: 1 else: 0)

fn indent(content: String) String:
	var out = ""
	for line in content.lines():
		out += f"    {line}\n"
	return out

// Regenerates expectations from the binary given by `--ms`.
export fn record_command(
	args: Args,
	environment: Map[String, String],
) Result[Int, String]:
	found := load(args, environment)?
	chosen := pick(found.fixtures, args.filter()?)
	ctx := context(args, "ms", environment)?
	note(f"recording {chosen.length()} fixtures from {ctx.ms}")

	options := RecordOptions(
		jobs: args.jobs()?,
		check_stable: not args.has("no-stable-check"),
		prune: args.has("prune"),
		only_missing: args.has("only-missing"),
	)
	summary := record(ctx, chosen, options)
	print(
		f"{summary.written} written, {summary.unchanged} unchanged, {summary.rejected.length()} rejected"
	)
	for item in summary.rejected:
		print(
			f"REJECTED {item.id}{if options.prune: " (deleted)" else: ""}\n{indent(item.reason)}"
		)
	return ok(if summary.rejected.is_empty(): 0 else: 1)

// Runs two binaries (`--a`, `--b`) on the corpus and compares them directly.
export fn diff_command(args: Args, environment: Map[String, String]) Result[Int, String]:
	found := load(args, environment)?
	chosen := pick(found.fixtures, args.filter()?)
	a := context(args, "a", environment)?
	var b = context(args, "b", environment)?
	b.scratch += "-b"

	cases := diff_binaries(a, b, chosen, args.jobs()?)
	print_lines(summary_lines(cases))

	label := f"{a.ms} vs {b.ms}"
	write_reports(args, label, cases)?
	return ok(if has_regressions(cases): 1 else: 0)
