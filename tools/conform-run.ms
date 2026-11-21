// The conformance corpus runner, in Manuscript. Usage from the repository root:
//   ms run tools/conform-run.ms -- <list|stats|lint|run|record|diff> [options]
// `list`, `stats` and `lint` read the corpus; the other commands run an `ms` binary on it.
import (
	stderr from "@std/io/io.ms",
	arguments, environment from "@std/os/env.ms",

	parse_args from "./conform/args.ms",
	diff_command, record_command, run_command from "./conform/commands.ms",
	lint_lines, list_lines, stats_lines from "./conform/corpus.ms",
	discover from "./conform/fixture.ms",
)

USAGE := """
conform-run: conformance corpus runner for any `ms` binary

usage: ms run tools/conform-run.ms -- <command> [options]

commands:
  run       run the corpus against --ms and compare with the recorded expectations
  record    regenerate expectations from the binary given by --ms
  diff      run two binaries (--a, --b) on the corpus and compare them directly;
            --env-a/--env-b KEY=VALUE set the environment of one side (e.g. --env-b MS_VECTORIZE=off)
  list      list fixtures (id, phase, tags)
  stats     count fixtures per phase and tag
  lint      validate fixture metadata and expectation files

selection (run, record, diff, list, stats):
  --corpus DIR        fixtures directory (default: tests/conformance/fixtures above the cwd)
  --tag T[,T]         only fixtures with any of these tags (repeatable)
  --exclude-tag T     skip fixtures with this tag
  --phase P[,P]       parse, check, run or test
  --id TEXT           only fixtures whose id contains TEXT
  --shard I/N         every Nth fixture starting at I (0-based) for parallel CI jobs
  --jobs N            parallel fixtures (default: every core)
  --timeout-scale F   multiply every timeout

run options:
  --ms PATH           binary under test (default: $MS, ./ms, or ms on PATH)
  --expect-fail FILE  allowlist of known failures (ids or prefix*); only others fail the run
  --write-expect-fail FILE   write the current failures as an allowlist
  --json FILE         machine-readable report
  --markdown FILE     markdown report (pass rate per tag and phase, failing fixtures with diffs)
  --max-failures N    failures shown in the markdown report (default 100)
  --strict            also fail on unexpected passes (allowlist entries that now pass)

record options:
  --no-stable-check   do not run each fixture twice to prove determinism
  --prune             delete fixtures that are unstable or cannot be recorded
  --only-missing      keep existing expectations
"""

fn usage_error(message: String) Int:
	stderr().write(f"conform-run: {message}\n").get()
	return 2

fn print_lines(lines: List[String]) Void:
	for line in lines:
		print(line)

fn main() Int:
	items := arguments()

	if items.is_empty():
		print(USAGE)
		return 2

	command := items[0]

	if command == "help" or command == "--help" or command == "-h":
		print(USAGE)
		return 0

	parsed := parse_args(items.slice(1, items.length()).get())
	if parsed.is_error(): return usage_error(parsed.err())

	args := parsed.get()

	if args.has("help"):
		print(USAGE)
		return 0

	env := environment().get_or(Map[String, String]())
	corpus := args.corpus(env)
	if corpus.is_error(): return usage_error(corpus.err())

	filter := args.filter()
	if filter.is_error(): return usage_error(filter.err())

	if command == "lint":
		lines := lint_lines(corpus.get())
		print_lines(lines.get())
		return if lines.get().length() == 1: 0 else: 1

	found := discover(corpus.get())

	if command == "list":
		print_lines(list_lines(found.fixtures, filter.get()))
		return 0

	if command == "stats":
		print_lines(stats_lines(found.fixtures, filter.get()))
		return 0

	var result: Result[Int, String] = ok(0)

	if command == "run":
		result = run_command(args, env)
	else if command == "record":
		result = record_command(args, env)
	else if command == "diff":
		result = diff_command(args, env)
	else:
		return usage_error(f"unknown command {command}; try --help")

	if result.is_error(): return usage_error(result.err())

	return result.get()
