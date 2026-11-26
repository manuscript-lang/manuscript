// conform: tags=closures,control-flow,faults,formatter,interpolation,lists,match,modules,mutation,parser,records,stdlib-fs,stdlib-io,stdlib-json,stdlib-process,stdlib-testing,strings,testing,tier-io,try-result
// conform: phase=parse
// conform: origin=scripts/conformance.ms
import (
	parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	GlobOptions, glob from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	expect_equal, expect_false, expect_some, expect_true, fail from "@std/test/test.ms",
)

// Run from the repository root: ms run scripts/conformance.ms -- /absolute/path/to/ms
// all 0 1. Each source file keeps its own compiler graph, process, host roots and test
// report.
type Summary {
	available Int
	selected Int
	passed Int
	failed Int
	skipped Int
	not_run Int
}

type Case {
	name String
	status String
}

type FixtureError {
	file String
	phase String
	failure String
}

type Report {
	format Int
	completed Bool
	exit_code Int
	tests List[Case]
	summary Summary
	fixture_errors List[FixtureError] = []
}

fn validate(report Report) Result[Void, Error] {
	report.format | expect_equal(expected: 1)?
	report.completed | expect_true?
	report.exit_code | expect_equal(expected: 0)?
	report.fixture_errors.is_empty() | expect_true?
	(report.summary.available > 0) | expect_true?
	report.summary.selected | expect_equal(expected: report.summary.available)?
	report.summary.failed | expect_equal(expected: 0)?
	report.summary.not_run | expect_equal(expected: 0)?
	report.tests.length() | expect_equal(expected: report.summary.selected)?
	(
		(report.summary.passed + report.summary.skipped)
		| expect_equal(expected: (report.summary.selected))?
	)

	var passed = 0
	var skipped = 0

	for entry in report.tests {
		if entry.status == "passed" {
			passed += 1
		} else if entry.status == "skipped" {
			skipped += 1
		} else {
			return fail(f"{entry.name}: incomplete or failed test ({entry.status})")
		}
	}

	passed | expect_equal(expected: report.summary.passed)?
	skipped | expect_equal(expected: report.summary.skipped)?
}

fn inventory(suite String) Result[List[String], Error] {
	var files List[String] = []

	if suite == "all" or suite == "core" {
		core := glob("tests/e2e/testdata/accept", GlobOptions(patterns: ["*.ms"]))?
		core.is_empty() | expect_false?
		for file in core {
			files.append(f"tests/e2e/testdata/accept/{file.path}")
		}

		projects := glob(
			"tests/e2e/testdata/projects",
			GlobOptions(patterns: ["*/conformance_test.ms"]),
		)?
		projects.is_empty() | expect_false?
		for file in projects {
			files.append(f"tests/e2e/testdata/projects/{file.path}")
		}
		for file in [
			"examples/hello/test.ms", "examples/tooling-demo/src/math.ms",
			"pkg/tooling/format/testdata/compact.input.ms",
			"pkg/tooling/format/testdata/compact.golden.ms"
		] {
			files.append(file)
		}
	}

	if suite == "all" or suite == "stdlib" {
		library := glob("tests/e2e/testdata/stdlib", GlobOptions(patterns: ["*.ms"]))?
		library.is_empty() | expect_false?
		for file in library {
			files.append(f"tests/e2e/testdata/stdlib/{file.path}")
		}
	}

	files.is_empty() | expect_false?
	return ok(files.sorted((left, right) => left.compare(right)))
}

fn selected(index Int, shard Int, count Int) Bool {
	return index % count == shard
}

fn run_conformance(args List[String]) Result[Void, Error] {
	if args.length() != 4 {
		return fail(
			"usage: conformance <ms executable> <all|core|stdlib> <shard> <count>"
		)
	}

	ms := args[0]
	suite := args[1]
	(suite == "all" or suite == "core" or suite == "stdlib") | expect_true?

	shard := (
		args[2]
		| .parse_int()
		| expect_some?
	)
	count := (
		args[3]
		| .parse_int()
		| expect_some?
	)
	(count > 0 and shard >= 0 and shard < count) | expect_true?

	files := inventory(suite)?
	var index = 0
	var failed = 0
	var ran = 0

	for file in files {
		if selected(index, shard, count) {
			ran += 1
			emit(f"TEST {file}")?

			result := run_file(ms, file.clone())

			match result {
				ok(_) => emit(f"PASS {file}")?
				error(cause) => {
					emit(f"FAIL {file}: {cause.message}")?
					failed += 1
				}
			}
		}

		index += 1
	}

	emit(f"{ran} files, {failed} failed")?
	failed | expect_equal(expected: 0)?
}

fn run_file(ms String, file String) Result[Void, Error] {
	output := run(
		ms,
		["test", file.clone(), "--json", "--timeout=30s"],
		RunOptions(timeout: 3.minutes(), max_output_bytes: 16000000),
	).wait()?
	text := output.stdout.decode_utf8() | expect_some?
	stderr := output.stderr.decode_utf8() | expect_some?

	match check_output(output.exit_code, text) {
		ok(_) => return ok()
		error(cause) => {
			emit(f"{text}\n{stderr}")?
			return error(cause)
		}
	}
}

fn check_output(status Int, text String) Result[Void, Error] {
	status | expect_equal(expected: 0)?

	report := parse[Report](text)?
	return validate(report)
}

export fn main() Int {
	match run_conformance(arguments()) {
		ok(_) => return 0
		error(cause) => {
			_written := stdout().write(f"{cause.message}\n")
			return 1
		}
	}
}

test "reports require complete nonempty executions and count explicit skips" {
	var report = Report(
		1,
		true,
		0,
		[Case("pass", "passed"), Case("skip", "skipped")],
		Summary(2, 2, 1, 0, 1, 0),
	)
	validate(report)?
	report.completed = false
	validate(report).is_error() | expect_true?
	report.completed = true
	report.summary.not_run = 1
	validate(report).is_error() | expect_true?
	report.summary.not_run = 0
	report.tests = [Case("pass", "failed"), Case("skip", "skipped")]
	validate(report).is_error() | expect_true?
	(
		validate(Report(1, true, 0, [], Summary(0, 0, 0, 0, 0, 0))).is_error()
		| expect_true?
	)
	check_output(1, "{}").is_error() | expect_true?
	check_output(0, "not JSON").is_error() | expect_true?
}

test "shards cover every inventory entry exactly once" {
	for count in [1, 3, 4] {
		var index = 0

		while index < 179 {
			var hits = 0
			var shard = 0

			while shard < count {
				if selected(index, shard, count) { hits += 1 }
				shard += 1
			}

			hits | expect_equal(expected: 1)?
			index += 1
		}
	}
}

fn emit(text String) Result[Void, Error] {
	stdout().write(f"{text}\n")?
}

test "invalid suite and shard arguments fail before running children" {
	run_conformance([]).is_error() | expect_true?
	run_conformance(["ms", "unknown", "0", "1"]).is_error() | expect_true?
	run_conformance(["ms", "core", "0", "0"]).is_error() | expect_true?
	run_conformance(["ms", "core", "-1", "3"]).is_error() | expect_true?
	run_conformance(["ms", "core", "3", "3"]).is_error() | expect_true?
	run_conformance(["ms", "core", "no", "3"]).is_error() | expect_true?
}

test "child launch failures are returned to the fixture dispatcher" {
	run_file(".", "fixture.ms").is_error() | expect_true?
}

test "fixture lifecycle errors invalidate an otherwise successful report" {
	var report = Report(1, true, 0, [Case("pass", "passed")], Summary(1, 1, 1, 0, 0, 0))
	report.fixture_errors.append(
		FixtureError("fixture.ms", "after_all", "cleanup failed")
	)
	validate(report).is_error() | expect_true?
}
// expect-format: rewritten
// expect-formatted: import (
// expect-formatted: \tparse from "@std/data/json.ms",
// expect-formatted: \tstdout from "@std/io/io.ms",
// expect-formatted: \targuments from "@std/os/env.ms",
// expect-formatted: \tGlobOptions, glob from "@std/os/fs.ms",
// expect-formatted: \tRunOptions, run from "@std/os/process.ms",
// expect-formatted: \texpect_equal, expect_false, expect_some, expect_true, fail from "@std/test/test.ms",
// expect-formatted: )
// expect-formatted:
// expect-formatted: // Run from the repository root: ms run scripts/conformance.ms -- /absolute/path/to/ms
// expect-formatted: // all 0 1. Each source file keeps its own compiler graph, process, host roots and test
// expect-formatted: // report.
// expect-formatted: type Summary {
// expect-formatted: \tavailable, selected, passed, failed, skipped, not_run Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Case {
// expect-formatted: \tname, status String
// expect-formatted: }
// expect-formatted:
// expect-formatted: type FixtureError {
// expect-formatted: \tfile, phase, failure String
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Report {
// expect-formatted: \tformat Int
// expect-formatted: \tcompleted Bool
// expect-formatted: \texit_code Int
// expect-formatted: \ttests List[Case]
// expect-formatted: \tsummary Summary
// expect-formatted: \tfixture_errors List[FixtureError] = []
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn validate(report Report) Result[Void, Error] {
// expect-formatted: \treport.format | expect_equal(expected: 1)?
// expect-formatted: \treport.completed | expect_true?
// expect-formatted: \treport.exit_code | expect_equal(expected: 0)?
// expect-formatted: \treport.fixture_errors.is_empty() | expect_true?
// expect-formatted: \t(report.summary.available > 0) | expect_true?
// expect-formatted: \treport.summary.selected | expect_equal(expected: report.summary.available)?
// expect-formatted: \treport.summary.failed | expect_equal(expected: 0)?
// expect-formatted: \treport.summary.not_run | expect_equal(expected: 0)?
// expect-formatted: \treport.tests.length() | expect_equal(expected: report.summary.selected)?
// expect-formatted: \t(
// expect-formatted: \t\t(report.summary.passed + report.summary.skipped)
// expect-formatted: \t\t| expect_equal(expected: (report.summary.selected))?
// expect-formatted: \t)
// expect-formatted:
// expect-formatted: \tvar passed = 0
// expect-formatted: \tvar skipped = 0
// expect-formatted:
// expect-formatted: \tfor entry in report.tests {
// expect-formatted: \t\tif entry.status == "passed" {
// expect-formatted: \t\t\tpassed += 1
// expect-formatted: \t\t} else if entry.status == "skipped" {
// expect-formatted: \t\t\tskipped += 1
// expect-formatted: \t\t} else {
// expect-formatted: \t\t\treturn fail(f"{entry.name}: incomplete or failed test ({entry.status})")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tpassed | expect_equal(expected: report.summary.passed)?
// expect-formatted: \tskipped | expect_equal(expected: report.summary.skipped)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn inventory(suite String) Result[List[String], Error] {
// expect-formatted: \tvar files List[String] = []
// expect-formatted:
// expect-formatted: \tif suite == "all" or suite == "core" {
// expect-formatted: \t\tcore := glob("tests/e2e/testdata/accept", GlobOptions(patterns: ["*.ms"]))?
// expect-formatted: \t\tcore.is_empty() | expect_false?
// expect-formatted: \t\tfor file in core {
// expect-formatted: \t\t\tfiles.append(f"tests/e2e/testdata/accept/{file.path}")
// expect-formatted: \t\t}
// expect-formatted:
// expect-formatted: \t\tprojects := glob(
// expect-formatted: \t\t\t"tests/e2e/testdata/projects",
// expect-formatted: \t\t\tGlobOptions(patterns: ["*/conformance_test.ms"]),
// expect-formatted: \t\t)?
// expect-formatted: \t\tprojects.is_empty() | expect_false?
// expect-formatted: \t\tfor file in projects {
// expect-formatted: \t\t\tfiles.append(f"tests/e2e/testdata/projects/{file.path}")
// expect-formatted: \t\t}
// expect-formatted: \t\tfor file in [
// expect-formatted: \t\t\t"examples/hello/test.ms", "examples/tooling-demo/src/math.ms",
// expect-formatted: \t\t\t"pkg/tooling/format/testdata/compact.input.ms",
// expect-formatted: \t\t\t"pkg/tooling/format/testdata/compact.golden.ms"
// expect-formatted: \t\t] {
// expect-formatted: \t\t\tfiles.append(file)
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tif suite == "all" or suite == "stdlib" {
// expect-formatted: \t\tlibrary := glob("tests/e2e/testdata/stdlib", GlobOptions(patterns: ["*.ms"]))?
// expect-formatted: \t\tlibrary.is_empty() | expect_false?
// expect-formatted: \t\tfor file in library {
// expect-formatted: \t\t\tfiles.append(f"tests/e2e/testdata/stdlib/{file.path}")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tfiles.is_empty() | expect_false?
// expect-formatted: \treturn ok(files.sorted((left, right) => left.compare(right)))
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn selected(index, shard, count Int) Bool {
// expect-formatted: \treturn index % count == shard
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn run_conformance(args List[String]) Result[Void, Error] {
// expect-formatted: \tif args.length() != 4 {
// expect-formatted: \t\treturn fail(
// expect-formatted: \t\t\t"usage: conformance <ms executable> <all|core|stdlib> <shard> <count>"
// expect-formatted: \t\t)
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tms := args[0]
// expect-formatted: \tsuite := args[1]
// expect-formatted: \t(suite == "all" or suite == "core" or suite == "stdlib") | expect_true?
// expect-formatted:
// expect-formatted: \tshard := (
// expect-formatted: \t\targs[2]
// expect-formatted: \t\t| .parse_int()
// expect-formatted: \t\t| expect_some?
// expect-formatted: \t)
// expect-formatted: \tcount := (
// expect-formatted: \t\targs[3]
// expect-formatted: \t\t| .parse_int()
// expect-formatted: \t\t| expect_some?
// expect-formatted: \t)
// expect-formatted: \t(count > 0 and shard >= 0 and shard < count) | expect_true?
// expect-formatted:
// expect-formatted: \tfiles := inventory(suite)?
// expect-formatted: \tvar index = 0
// expect-formatted: \tvar failed = 0
// expect-formatted: \tvar ran = 0
// expect-formatted:
// expect-formatted: \tfor file in files {
// expect-formatted: \t\tif selected(index, shard, count) {
// expect-formatted: \t\t\tran += 1
// expect-formatted: \t\t\temit(f"TEST {file}")?
// expect-formatted:
// expect-formatted: \t\t\tresult := run_file(ms, file.clone())
// expect-formatted:
// expect-formatted: \t\t\tmatch result {
// expect-formatted: \t\t\t\tok(_) => emit(f"PASS {file}")?
// expect-formatted: \t\t\t\terror(cause) => {
// expect-formatted: \t\t\t\t\temit(f"FAIL {file}: {cause.message}")?
// expect-formatted: \t\t\t\t\tfailed += 1
// expect-formatted: \t\t\t\t}
// expect-formatted: \t\t\t}
// expect-formatted: \t\t}
// expect-formatted:
// expect-formatted: \t\tindex += 1
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \temit(f"{ran} files, {failed} failed")?
// expect-formatted: \tfailed | expect_equal(expected: 0)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn run_file(ms, file String) Result[Void, Error] {
// expect-formatted: \toutput := run(
// expect-formatted: \t\tms,
// expect-formatted: \t\t["test", file.clone(), "--json", "--timeout=30s"],
// expect-formatted: \t\tRunOptions(timeout: 3.minutes(), max_output_bytes: 16000000),
// expect-formatted: \t).wait()?
// expect-formatted: \ttext := output.stdout.decode_utf8() | expect_some?
// expect-formatted: \tstderr := output.stderr.decode_utf8() | expect_some?
// expect-formatted:
// expect-formatted: \tmatch check_output(output.exit_code, text) {
// expect-formatted: \t\tok(_) => return ok()
// expect-formatted: \t\terror(cause) => {
// expect-formatted: \t\t\temit(f"{text}\\n{stderr}")?
// expect-formatted: \t\t\treturn error(cause)
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn check_output(status Int, text String) Result[Void, Error] {
// expect-formatted: \tstatus | expect_equal(expected: 0)?
// expect-formatted:
// expect-formatted: \treport := parse[Report](text)?
// expect-formatted: \treturn validate(report)
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn main() Int {
// expect-formatted: \tmatch run_conformance(arguments()) {
// expect-formatted: \t\tok(_) => return 0
// expect-formatted: \t\terror(cause) => {
// expect-formatted: \t\t\t_written := stdout().write(f"{cause.message}\\n")
// expect-formatted: \t\t\treturn 1
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "reports require complete nonempty executions and count explicit skips" {
// expect-formatted: \tvar report = Report(
// expect-formatted: \t\t1,
// expect-formatted: \t\ttrue,
// expect-formatted: \t\t0,
// expect-formatted: \t\t[Case("pass", "passed"), Case("skip", "skipped")],
// expect-formatted: \t\tSummary(2, 2, 1, 0, 1, 0),
// expect-formatted: \t)
// expect-formatted: \tvalidate(report)?
// expect-formatted: \treport.completed = false
// expect-formatted: \tvalidate(report).is_error() | expect_true?
// expect-formatted: \treport.completed = true
// expect-formatted: \treport.summary.not_run = 1
// expect-formatted: \tvalidate(report).is_error() | expect_true?
// expect-formatted: \treport.summary.not_run = 0
// expect-formatted: \treport.tests = [Case("pass", "failed"), Case("skip", "skipped")]
// expect-formatted: \tvalidate(report).is_error() | expect_true?
// expect-formatted: \t(
// expect-formatted: \t\tvalidate(Report(1, true, 0, [], Summary(0, 0, 0, 0, 0, 0))).is_error()
// expect-formatted: \t\t| expect_true?
// expect-formatted: \t)
// expect-formatted: \tcheck_output(1, "{}").is_error() | expect_true?
// expect-formatted: \tcheck_output(0, "not JSON").is_error() | expect_true?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "shards cover every inventory entry exactly once" {
// expect-formatted: \tfor count in [1, 3, 4] {
// expect-formatted: \t\tvar index = 0
// expect-formatted:
// expect-formatted: \t\twhile index < 179 {
// expect-formatted: \t\t\tvar hits = 0
// expect-formatted: \t\t\tvar shard = 0
// expect-formatted:
// expect-formatted: \t\t\twhile shard < count {
// expect-formatted: \t\t\t\tif selected(index, shard, count) { hits += 1 }
// expect-formatted: \t\t\t\tshard += 1
// expect-formatted: \t\t\t}
// expect-formatted:
// expect-formatted: \t\t\thits | expect_equal(expected: 1)?
// expect-formatted: \t\t\tindex += 1
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn emit(text String) Result[Void, Error] {
// expect-formatted: \tstdout().write(f"{text}\\n")?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "invalid suite and shard arguments fail before running children" {
// expect-formatted: \trun_conformance([]).is_error() | expect_true?
// expect-formatted: \trun_conformance(["ms", "unknown", "0", "1"]).is_error() | expect_true?
// expect-formatted: \trun_conformance(["ms", "core", "0", "0"]).is_error() | expect_true?
// expect-formatted: \trun_conformance(["ms", "core", "-1", "3"]).is_error() | expect_true?
// expect-formatted: \trun_conformance(["ms", "core", "3", "3"]).is_error() | expect_true?
// expect-formatted: \trun_conformance(["ms", "core", "no", "3"]).is_error() | expect_true?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "child launch failures are returned to the fixture dispatcher" {
// expect-formatted: \trun_file(".", "fixture.ms").is_error() | expect_true?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "fixture lifecycle errors invalidate an otherwise successful report" {
// expect-formatted: \tvar report = Report(1, true, 0, [Case("pass", "passed")], Summary(1, 1, 1, 0, 0, 0))
// expect-formatted: \treport.fixture_errors.append(
// expect-formatted: \t\tFixtureError("fixture.ms", "after_all", "cleanup failed")
// expect-formatted: \t)
// expect-formatted: \tvalidate(report).is_error() | expect_true?
// expect-formatted: }
