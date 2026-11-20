// Recording expectations from the oracle, and comparing two binaries directly.
import (
	map_concurrent from "@std/concurrency/resilience.ms",
	JsonValue from "@std/data/json.ms",
	create_directory, exists, read_file, remove, write_file from "@std/os/fs.ms",
	seconds from "@std/time.ms",

	Output, execute from "./exec.ms",
	Fixture, phase_name from "./fixture.ms",
	compact, diff, number, object, pretty_line, text, with from "./json_util.ms",
	Ctx, observe from "./observe.ms",
	Case, Outcome from "./runner.ms",
)

export type RecordOptions:
	jobs: Int
	// Observe twice and refuse fixtures whose answers differ.
	check_stable: Bool
	// Delete fixtures that are unstable or cannot be recorded.
	prune: Bool
	// Keep existing expectations; only record fixtures without one.
	only_missing: Bool

export type Rejected:
	id: String
	reason: String

export type RecordSummary:
	written: Int = 0
	unchanged: Int = 0
	rejected: List[Rejected] = []

// The oracle's `ms version` text, stored in each expectation for provenance.
fn oracle_version(ms: String) String:
	out := execute(
		ms,
		["version"],
		".",
		"".to_bytes(),
		seconds(30),
		Map[String, String](),
	)
	return out.stdout.trim()

UNRECORDABLE := ["harness_error", "spawn_error", "timed_out", "unparsable_json"]

fn unrecordable(observation: JsonValue) String:
	for key in UNRECORDABLE:
		if observation.get(key).is_some():
			return f"observation has {key}: {compact(observation).chars().take(300).join("")}"
	if report := observation.get("report"):
		if report.get("unparsable_json").is_some(): return "ms test did not print JSON"
	return ""

type Recorded:
	// Empty when the fixture was skipped or rejected.
	document: String = ""
	skipped: Bool = false
	reason: String = ""

fn record_one(
	ctx: Ctx,
	fx: Fixture,
	version: String,
	options: RecordOptions,
	slot: String,
) Recorded:
	if options.only_missing and exists(fx.expected_path).get_or(false): return Recorded(
		skipped: true
	)

	first := observe(ctx, fx, slot)
	problem := unrecordable(first)
	if not problem.is_empty(): return Recorded(reason: problem)

	if options.check_stable and not fx.deterministic:
		second := observe(ctx, fx, f"{slot}-again")
		if difference := diff(first, second, 4):
			return Recorded(reason: f"unstable between runs:\n{difference}")

	var doc = with(object(), "format", number(1))
	doc = with(doc, "phase", text(phase_name(fx.phase)))
	doc = with(doc, "oracle", text(version))
	doc = with(doc, "expected", first)
	return Recorded(document: pretty_line(doc))

fn delete_fixture(fx: Fixture) Void:
	if fx.is_dir:
		void remove(fx.root, recursive: true)
		return

	void remove(fx.root)
	void remove(fx.expected_path)
	void remove(fx.root.cut_suffix(".ms").get_or(fx.root) + ".stdin")

export fn record(
	ctx: Ctx,
	fixtures: List[Fixture],
	options: RecordOptions,
) RecordSummary:
	version := oracle_version(ctx.ms)
	void create_directory(ctx.scratch, recursive: true)

	positions := fixtures.keys()
	results := map_concurrent(
		positions,
		options.jobs,
		fn at: record_one(ctx, fixtures[at], version, options, f"r{at}")
	).get_or([])
	void remove(ctx.scratch, recursive: true)

	var summary = RecordSummary()

	for at in positions:
		fx := fixtures[at]
		result := results[at]

		if result.skipped:
			summary.unchanged += 1
		else if not result.reason.is_empty():
			if options.prune: delete_fixture(fx)
			summary.rejected.append(
				Rejected(
					id: fx.id.clone(),
					reason: result.reason.clone(),
				)
			)
		else if same_file(fx.expected_path, result.document):
			summary.unchanged += 1
		else if write_file(fx.expected_path, result.document, replace: true).wait().is_ok():
			summary.written += 1
		else:
			summary.rejected.append(
				Rejected(
					id: fx.id.clone(),
					reason: "cannot write expectation",
				)
			)

	return summary

fn same_file(path: String, content: String) Bool:
	if data := read_file(path).wait():
		return data.decode_utf8().get_or("\u{0}") == content
	return false

// Runs two binaries on each fixture and compares their observations (no stored
// expectation).
export fn diff_binaries(a: Ctx, b: Ctx, fixtures: List[Fixture], jobs: Int) List[Case]:
	void create_directory(a.scratch, recursive: true)
	void create_directory(b.scratch, recursive: true)

	cases := map_concurrent(
		fixtures.keys(),
		jobs,
		fn at: compare_one(a, b, fixtures[at], f"d{at}")
	).get_or([])
	void remove(a.scratch, recursive: true)
	void remove(b.scratch, recursive: true)
	return cases

fn compare_one(a: Ctx, b: Ctx, fx: Fixture, slot: String) Case:
	left := observe(a, fx, slot)
	right := observe(b, fx, slot)
	difference := diff(left, right, 8)
	return Case(
		id: fx.id.clone(),
		tags: fx.tags.clone(),
		phase: fx.phase,
		outcome: if difference.is_none(): Outcome.Pass else: Outcome.Fail,
		millis: 0,
		diff: difference.get_or(""),
	)
