// The selection and run options of `ms test` and `ms bench`, read from what the command
// tree parsed: `--test`, `--match`, `--exclude`, `--filter`, `--list`, `--fail-fast`,
// `--repeat`, `--shuffle`, `--timeout`, `--runs`, `--seed`, `--fuzz`, and the bench flags.
// The words after `--` are the program's own arguments.
import (
	Matches from "@std/cli/command.ms",
	compile from "@std/regex.ms",
	Duration, parse_duration, seconds from "@std/time.ms",
)

// Each test gets this long unless `--timeout` says otherwise.
DEFAULT_TIMEOUT_SECONDS := 60

export type TestOptions:
	names: List[String] = []
	matching: String = ""
	exclude: String = ""
	filter: String = ""
	list: Bool = false
	fail_fast: Bool = false
	repeat: Int = 1
	// The seed of `--shuffle`, when given.
	shuffle: Int? = none
	// The limit of one test; none when `--timeout=0` disabled it.
	timeout: Duration? = seconds(DEFAULT_TIMEOUT_SECONDS)
	// Whether `--timeout` was given, so `--fuzz` knows not to replace it.
	timeout_set: Bool = false
	// Cases per property (`MS_TEST_RUNS`).
	runs: Int? = none
	// First property case seed (`MS_TEST_SEED`).
	seed: Int? = none
	// Per-property time budget (`MS_TEST_FUZZ_MS`); properties then run until it
	// expires.
	fuzz: Duration? = none
	// Target duration of one sample (`--time`).
	bench_time: Duration? = none
	// Timed samples per bench (`--samples`).
	bench_samples: Int? = none
	// Fixed iterations per sample (`--iterations`); calibrated when unset.
	bench_iterations: Int? = none
	// A saved `ms bench --json` result whose work counters this run is held to.
	baseline: String = ""
	// The percentage a work counter may rise over the baseline (`--fail-over`).
	fail_over: Float? = none
	// Count MIR operations (`--ops`).
	ops: Bool = false
	// Arguments for the programs under test.
	program: List[String] = []

fn on(m: Matches, name: String) Bool:
	return m.string_or_none(name).get_or("") == "true"

fn positive(m: Matches, name: String) Result[Int?, String]:
	text := m.string_or_none(name)
	if text.is_none(): return ok(none)

	number := text.get().parse_int()
	if number.is_none() or number.get() <= 0: return error(
		f"invalid --{name}; use a positive integer"
	)

	return ok(number)

fn integer(m: Matches, name: String) Result[Int?, String]:
	text := m.string_or_none(name)
	if text.is_none(): return ok(none)

	number := text.get().parse_int()
	if number.is_none(): return error(f"invalid --{name}; use an integer seed")

	return ok(number)

// The duration of `--name`, when given, that is at least `least` nanoseconds.
fn duration(
	m: Matches,
	name: String,
	least: Int,
	advice: String,
) Result[Duration?, String]:
	text := m.string_or_none(name)
	if text.is_none(): return ok(none)

	parsed := parse_duration(text.get())
	if parsed.is_error() or parsed.get().nanos < least: return error(
		f"invalid --{name} {quoted(text.get())}; use {advice}"
	)

	return ok(parsed.get())

fn pattern(m: Matches, name: String) Result[String, String]:
	text := m.string_or_none(name).get_or("")
	if text.is_empty(): return ok("")

	compiled := compile(text)
	if compiled.is_error():
		return error(
			f"invalid --{name}: {compiled.err().message}; supply a valid regular expression"
		)

	return ok(text)

// `value` as Rust's `{:?}` prints a string.
fn quoted(value: String) String:
	return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

// The options one `ms test` or `ms bench` command line selected, each checked.
export fn test_options(m: Matches) Result[TestOptions, String]:
	var options = TestOptions(
		names: m.list("test"),
		filter: m.string_or_none("filter").get_or(""),
		baseline: m.string_or_none("baseline").get_or(""),
		list: on(m, "list"),
		fail_fast: on(m, "fail-fast"),
		ops: on(m, "ops"),
		program: m.passthrough.clone(),
	)
	options.matching = pattern(m, "match")?
	options.exclude = pattern(m, "exclude")?
	options.repeat = positive(m, "repeat")?.get_or(1)
	options.runs = positive(m, "runs")?
	options.bench_samples = positive(m, "samples")?
	options.bench_iterations = positive(m, "iterations")?
	options.shuffle = integer(m, "shuffle")?
	options.seed = integer(m, "seed")?
	options.bench_time = duration(
		m,
		"time",
		1000000,
		"a duration of at least 1ms such as 200ms or 1s",
	)?
	options.fuzz = duration(m, "fuzz", 1, "a positive duration such as 30s or 5m")?

	limit := duration(m, "timeout", 0, "a duration such as 30s or 2m, or 0 to disable")?

	if given := limit:
		options.timeout_set = true
		options.timeout = if given.nanos > 0: given else: none

	if bound := m.string_or_none("fail-over"):
		percent := bound.trim_end_chars("%").parse_float()
		if percent.is_none() or percent.get() < 0.0:
			return error("invalid --fail-over; use a percentage such as 3 or 3%")

		options.fail_over = percent.get()

	// A fuzz budget applies to every property in a test, so the default limit would cut
	// it short.
	if options.fuzz.is_some() and not options.timeout_set: options.timeout = none
	return ok(options)
