// Running the selected fixtures in parallel and judging each against its recorded
// expectation.
import (
	map_concurrent from "@std/concurrency/resilience.ms",
	JsonValue from "@std/data/json.ms",
	create_directory, list, read_file, remove from "@std/os/fs.ms",
	Instant, monotonic from "@std/time.ms",

	Fixture, Phase, phase_name, weight from "./fixture.ms",
	bool_member, diff, string_member from "./json_util.ms",
	Ctx, observe, observe_check_batch, observe_test_batch from "./observe.ms",
	ExpectFail, load_expected from "./select.ms",
)

export enum Outcome:
	Pass
	// Failed and not on the allowlist.
	Fail
	// Failed but listed in the expect-fail file.
	ExpectedFail
	// Passed although listed in the expect-fail file.
	UnexpectedPass
	// The fixture has no recorded expectation.
	Unrecorded

// The name `Outcome` prints with in reports.
export fn outcome_name(outcome: Outcome) String:
	if outcome == Outcome.Pass: return "Pass"
	if outcome == Outcome.Fail: return "Fail"
	if outcome == Outcome.ExpectedFail: return "ExpectedFail"
	if outcome == Outcome.UnexpectedPass: return "UnexpectedPass"

	return "Unrecorded"

export type Case:
	id: String
	tags: List[String]
	phase: Phase
	outcome: Outcome
	millis: Int
	diff: String

fn unrecorded(fx: Fixture, reason: String) Case:
	return Case(
		id: fx.id.clone(),
		tags: fx.tags.clone(),
		phase: fx.phase,
		outcome: Outcome.Unrecorded,
		millis: 0,
		diff: reason,
	)

// Judges `actual` against the recorded expectation of `fx`.
fn judge(fx: Fixture, allow: ExpectFail, actual: JsonValue, millis: Int) Case:
	loaded := load_expected(fx)
	if loaded.is_error(): return unrecorded(fx, loaded.err())

	difference := diff(loaded.get(), actual, 8)
	passed := difference.is_none()
	listed := allow.contains(fx.id)
	var outcome = Outcome.Pass
	if passed and listed: outcome = Outcome.UnexpectedPass
	if not passed and not listed: outcome = Outcome.Fail
	if not passed and listed: outcome = Outcome.ExpectedFail
	return Case(
		id: fx.id.clone(),
		tags: fx.tags.clone(),
		phase: fx.phase,
		outcome: outcome,
		millis: millis,
		diff: difference.get_or(""),
	)

fn elapsed_millis(started: Instant) Int:
	return monotonic().difference(started).to_milliseconds()

// Runs one fixture on `ctx.ms` and judges it.
export fn check_one(ctx: Ctx, fx: Fixture, allow: ExpectFail, slot: String) Case:
	started := monotonic()
	loaded := load_expected(fx)
	if loaded.is_error(): return unrecorded(fx, loaded.err())

	actual := observe(ctx, fx, slot)
	return judge(fx, allow, actual, elapsed_millis(started))

// Check fixtures observed by one `ms check --each` process. Each load of the standard
// library costs more than checking a fixture, so a batch is a few dozen, small enough
// to spread over the workers.
CHECK_BATCH := 24

fn check_batch(
	ctx: Ctx,
	batch: List[Fixture],
	allow: ExpectFail,
	slot: String,
) List[Case]:
	started := monotonic()
	observed := observe_check_batch(ctx, batch, slot)
	share := elapsed_millis(started) / max_one(batch.length())
	var cases = List[Case]()

	for at in 0..batch.length():
		var judged = judge(batch[at], allow, observed[at], 0)
		if judged.outcome != Outcome.Unrecorded: judged.millis = share
		cases.append(judged)

	return cases

fn max_one(count: Int) Int:
	if count < 1: return 1
	return count

// Fixtures of one `ms test` build: enough that the test runner and shared modules
// compile once for many, few enough that a mismatch reruns little.
TEST_BATCH := 12
// Imports that reach files, ports, processes or the clock, state one process would
// share between fixtures. A fixture that names one runs alone.
SHARED_STATE := ["@std/os/", "@std/net/", "@std/process", "@std/time"]

fn lines_are_clean(stdout: String) Bool:
	lines := stdout.split("\n")
	if lines.length() <= 2: return false

	for at in 0..lines.length() - 2:
		if not (lines[at].starts_with("RUN ") or lines[at].starts_with("PASS ")): return false
	return true

fn count_member(report: JsonValue, key: String) Int:
	if summary := report.get("summary"):
		if member := summary.get(key): return member.as_int().get_or(-1)
	return -1

// True when `fx` is a single-file test fixture whose recorded outcome is a clean pass
// that one batched run can reproduce: every test passed, nothing on stderr, and a
// stdout of only the `RUN` and `PASS` lines and the summary.
fn batchable(ctx: Ctx, fx: Fixture) Bool:
	if fx.phase != Phase.Test or ctx.leaks or not fx.args.is_empty(): return false
	if not fx.stdin.is_empty() or fx.timeout_secs >= 0 or fx.is_dir: return false

	source := read_file(fx.root).wait().get_or("".to_bytes()).decode_utf8()
	if source.is_none(): return false
	if SHARED_STATE.any(fn name: source.get().contains(name)): return false

	loaded := load_expected(fx)
	if loaded.is_error(): return false

	expected := loaded.get()
	report := expected.get("report")
	if report.is_none(): return false

	var exit_code = -1
	if member := expected.get("exit_code"): exit_code = member.as_int().get_or(-1)
	if exit_code != 0: return false
	if (
		count_member(report.get(), "failed") != 0
		or count_member(report.get(), "skipped") != 0
	): return false

	diagnostics := report.get().get("diagnostics")
	if diagnostics.is_none(): return false
	if not diagnostics.get().as_list().get_or([JsonValue.Null]).is_empty(): return false
	if string_member(expected, "stderr") != "" or not expected.get("stderr").is_some(): return false

	return lines_are_clean(string_member(report.get(), "stdout"))

// Groups `eligible` fixture positions into batches whose entry file names differ (a
// test name is
// `file.ms::name`, so equal names could not be told apart).
fn test_batches(fixtures: List[Fixture], eligible: List[Int]) List[List[Int]]:
	var batches = List[List[Int]]()

	for at in eligible:
		var placed = false

		for slot in 0..batches.length():
			if placed: break

			batch := batches[slot]
			if batch.length() >= TEST_BATCH: continue
			if batch.any(fn j: fixtures[j].entry == fixtures[at].entry): continue

			var grown = batch.clone()
			grown.append(at)
			batches.set(slot, grown)
			placed = true

		if not placed: batches.append([at])

	return batches

fn test_batch(
	ctx: Ctx,
	batch: List[Fixture],
	allow: ExpectFail,
	slot: String,
) List[Case]:
	observed := observe_test_batch(ctx, batch, slot)
	var cases = List[Case]()

	for at in 0..batch.length():
		started := monotonic()

		if actual := observed[at]:
			judged := judge(batch[at], allow, actual, elapsed_millis(started))

			if (
				judged.outcome == Outcome.Pass
				or judged.outcome == Outcome.UnexpectedPass
			):
				cases.append(judged)
				continue

		cases.append(check_one(ctx, batch[at], allow, f"{slot}-{at}"))

	return cases

// One unit of work: positions in the fixture list, run as one process or as a batch.
type Work:
	at: List[Int]
	slot: String

fn pick(fixtures: List[Fixture], at: List[Int]) List[Fixture]:
	var batch = List[Fixture]()
	for index in at:
		batch.append(fixtures[index].clone())
	return batch

fn run_work(ctx: Ctx, fixtures: List[Fixture], allow: ExpectFail, work: Work) List[Case]:
	first := fixtures[work.at[0]]
	if first.phase == Phase.Check: return check_batch(
		ctx,
		pick(fixtures, work.at),
		allow,
		work.slot,
	)
	if work.at.length() > 1: return test_batch(
		ctx,
		pick(fixtures, work.at),
		allow,
		work.slot,
	)

	return [check_one(ctx, first, allow, work.slot)]

// Runs all `fixtures`, `jobs` at a time, and returns one case per fixture in the same
// order.
export fn run_all(
	ctx: Ctx,
	fixtures: List[Fixture],
	allow: ExpectFail,
	jobs: Int,
) List[Case]:
	void create_directory(ctx.scratch, recursive: true)

	// One work item is a fixture, or a batch of check or test fixtures.
	var singles = List[List[Int]]()
	var checks = List[Int]()
	var tests = List[Int]()

	for at in 0..fixtures.length():
		if fixtures[at].phase == Phase.Check:
			checks.append(at)
		else if batchable(ctx, fixtures[at]):
			tests.append(at)
		else:
			singles.append([at])

	var items = singles.concat(test_batches(fixtures, tests))

	// A batch is sized so every worker gets some, however few the check fixtures are.
	size := (
		checks.length() / max_one(jobs)
		+ (if checks.length() % max_one(jobs) > 0: 1 else: 0)
	)
	chunk := if size < 1: 1 else if size > CHECK_BATCH: CHECK_BATCH else: size

	// Longest first: a big program that starts last runs alone while the other workers
	// idle. Check batches are short and go at the end.
	var weights = Map[Int, Int]()

	for slot in 0..items.length():
		var total = 0
		for index in items[slot]:
			total += weight(fixtures[index])
		weights.add(slot, total)

	ranked := items.keys().sorted_by_key(fn slot: 0 - weights.get(slot).get_or(0))
	var ordered = List[List[Int]]()
	for slot in ranked:
		ordered.append(items[slot].clone())
	for start in 0..(checks.length() + chunk - 1) / chunk:
		ordered.append(
			checks.slice(
				start * chunk,
				min_of((start + 1) * chunk, checks.length()),
			).get_or([]).clone()
		)

	var work = List[Work]()
	for slot in 0..ordered.length():
		work.append(Work(at: ordered[slot].clone(), slot: f"u{slot}"))

	finished := map_concurrent(
		work,
		max_one(jobs),
		fn item: run_work(ctx, fixtures, allow, item)
	).get_or([])
	var by_position = Map[Int, Case]()

	for slot in 0..ordered.length():
		cases := finished.get_or(slot, [])
		for place in 0..ordered[slot].length():
			by_position.add(ordered[slot][place], cases[place].clone())

	var out = List[Case]()
	for at in 0..fixtures.length():
		out.append(by_position.get(at).get())
	void remove(ctx.scratch, recursive: true)
	return out

fn min_of(a: Int, b: Int) Int:
	if a < b: return a
	return b
