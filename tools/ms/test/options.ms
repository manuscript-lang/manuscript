// The selection and run options `ms test` reads from the flags the command line
// forwards:
// `--test=`, `--match=`, `--exclude=`, `--filter=`, `--list`, `--fail-fast`, `--repeat=`,
// `--shuffle=`, `--timeout=`, `--runs=`, `--seed=`, `--fuzz=`. The first argument that is not
// one of them starts the program's own arguments.
import Duration, nanoseconds, parse_duration, seconds from "@std/time.ms"

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

fn positive(value: String, message: String) Result[Int, String]:
	number := value.parse_int().ok_or(message.clone())?
	if number <= 0: return error(message.clone())

	return ok(number)

fn duration_of(value: String, message: String) Result[Duration, String]:
	parsed := parse_duration(value)
	if parsed.is_error(): return error(message.clone())

	return ok(parsed.get())

// Applies one `--name=value` option; false when `name` is not a test option.
fn apply(var options: TestOptions, name: String, value: String) Result[Bool, String]:
	if name == "--test":
		options.names.append(value.clone())
	else if name == "--match":
		options.matching = value.clone()
	else if name == "--exclude":
		options.exclude = value.clone()
	else if name == "--filter":
		options.filter = value.clone()
	else if name == "--repeat":
		options.repeat = positive(value, "invalid --repeat; use a positive integer")?
	else if name == "--shuffle":
		options.shuffle = (
			value
			.parse_int()
			.ok_or("invalid --shuffle; use an integer seed")?
		)
	else if name == "--runs":
		options.runs = positive(value, "invalid --runs; use a positive integer")?
	else if name == "--seed":
		options.seed = value.parse_int().ok_or("invalid --seed; use an integer seed")?
	else if name == "--fuzz":
		message := f"invalid --fuzz {quoted(value)}; use a positive duration such as 30s or 5m"
		budget := duration_of(value, message)?
		if budget.nanos <= 0: return error(message)

		options.fuzz = budget
	else if name == "--time":
		message := f"invalid --time {quoted(value)}; use a duration of at least 1ms such as 200ms or 1s"
		budget := duration_of(value, message)?
		if budget.nanos < 1000000: return error(message)

		options.bench_time = budget
	else if name == "--samples":
		options.bench_samples = positive(
			value,
			"invalid --samples; use a positive integer",
		)?
	else if name == "--iterations":
		options.bench_iterations = positive(
			value,
			"invalid --iterations; use a positive integer",
		)?
	else if name == "--baseline":
		options.baseline = value.clone()
	else if name == "--fail-over":
		message := "invalid --fail-over; use a percentage such as 3 or 3%"
		bound := value.trim_end_chars("%").parse_float()
		if bound.is_none() or bound.get() < 0.0: return error(message)

		options.fail_over = bound.get()
	else if name == "--timeout":
		options.timeout_set = true

		message := f"invalid --timeout {quoted(value)}; use a duration such as 30s or 2m, or 0 to disable"
		limit := duration_of(value, message)?
		if limit.nanos < 0: return error(message)

		options.timeout = if limit.nanos > 0: limit else: none
	else:
		return ok(false)

	return ok(true)

// `value` as Rust's `{:?}` prints a string.
fn quoted(value: String) String:
	return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

export fn parse_test_options(args: List[String]) Result[TestOptions, String]:
	var options = TestOptions()
	var at = 0

	while at < args.length():
		arg := args[at]

		if arg == "--":
			at += 1
			break

		if arg == "--list":
			options.list = true
		else if arg == "--fail-fast":
			options.fail_fast = true
		else if arg == "--ops":
			options.ops = true
		else:
			pair := arg.split_once("=")
			if pair.is_none(): break
			if not apply(options, pair.get().before, pair.get().after)?: break

		at += 1

	// A fuzz budget applies to every property in a test, so the default limit would cut
	// it short.
	if options.fuzz.is_some() and not options.timeout_set: options.timeout = none
	options.program = args.slice(at, args.length()).get_or([]).clone()
	return ok(options)
