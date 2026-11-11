// conform: tags=closures,control-flow,faults,interpolation,lists,match,modules,mutation,records,stdlib-fs,stdlib-io,stdlib-json,stdlib-process,stdlib-testing,strings,testing,tier-io,try-result
// conform: phase=test
// conform: origin=scripts/conformance.ms
import (
    expect_equal,
    expect_false,
    expect_some,
    expect_true,
    fail
) from "@std/test/test.ms"
import stdout from "@std/io/io.ms"
import arguments from "@std/os/env.ms"
import glob, GlobOptions from "@std/os/fs.ms"
import RunOptions, run from "@std/os/process.ms"
import parse from "@std/data/json.ms"

// Run from the repository root: ms run scripts/conformance.ms -- /absolute/path/to/ms all 0 1.
// Each source file keeps its own compiler graph, process, host roots and test report.
type Summary:
    available: Int
    selected: Int
    passed: Int
    failed: Int
    skipped: Int
    not_run: Int

type Case:
    name: String
    status: String

type FixtureError:
    file: String
    phase: String
    failure: String

type Report:
    format: Int
    completed: Bool
    exit_code: Int
    tests: List[Case]
    summary: Summary
    fixture_errors: List[FixtureError] = []

fn validate(report: Report) Result[Unit, Error]:
    report.format | expect_equal(expected: 1)?
    report.completed | expect_true?
    report.exit_code | expect_equal(expected: 0)?
    report.fixture_errors.is_empty() | expect_true?
    (report.summary.available > 0) | expect_true?
    report.summary.selected | expect_equal(expected: report.summary.available)?
    report.summary.failed | expect_equal(expected: 0)?
    report.summary.not_run | expect_equal(expected: 0)?
    report.tests.length() | expect_equal(expected: report.summary.selected)?
    (report.summary.passed + report.summary.skipped) | expect_equal(
        expected: (report.summary.selected)
    )?

    var passed = 0
    var skipped = 0

    for entry in report.tests:
        if entry.status == "passed":
            passed = passed + 1
        else if entry.status == "skipped":
            skipped = skipped + 1
        else:
            return fail("{entry.name}: incomplete or failed test ({entry.status})")

    passed | expect_equal(expected: report.summary.passed)?
    skipped | expect_equal(expected: report.summary.skipped)?

fn inventory(suite: String) Result[List[String], Error]:
    var files: List[String] = []

    if suite == "all" or suite == "core":
        core := glob(
            "tests/e2e/testdata/accept", GlobOptions(patterns: ["*.ms"])
        )?
        core.is_empty() | expect_false?
        for file in core: files.append("tests/e2e/testdata/accept/{file.path}")

        projects := glob(
            "tests/e2e/testdata/projects",
            GlobOptions(patterns: ["*/conformance_test.ms"])
        )?
        projects.is_empty() | expect_false?
        for file in projects: files.append("tests/e2e/testdata/projects/{file.path}")
        for file in [
            "examples/hello/test.ms", "examples/tooling-demo/src/math.ms",
            "pkg/tooling/format/testdata/compact.input.ms",
            "pkg/tooling/format/testdata/compact.golden.ms"
        ]:
            files.append(file)

    if suite == "all" or suite == "stdlib":
        library := glob(
            "tests/e2e/testdata/stdlib", GlobOptions(patterns: ["*.ms"])
        )?
        library.is_empty() | expect_false?
        for file in library: files.append("tests/e2e/testdata/stdlib/{file.path}")

    files.is_empty() | expect_false?
    return ok(files.sorted(fn left, right: left.compare(right)))

fn selected(index: Int, shard: Int, count: Int) Bool:
    return index % count == shard

fn run_conformance(args: List[String]) Result[Unit, Error]:
    if args.length() != 4:
        return fail(
            "usage: conformance <ms executable> <all|core|stdlib> <shard> <count>"
        )

    ms := args.get(0)
    suite := args.get(1)
    (suite == "all" or suite == "core" or suite == "stdlib") | expect_true?

    shard := args.get(2) | .parse_int() | expect_some?
    count := args.get(3) | .parse_int() | expect_some?
    (count > 0 and shard >= 0 and shard < count) | expect_true?

    files := inventory(suite)?
    var index = 0
    var failed = 0
    var ran = 0

    for file in files:
        if selected(index, shard, count):
            ran = ran + 1
            emit("TEST {file}")?

            result := run_file(ms, file.clone())

            match result:
                ok(_): emit("PASS {file}")?
                error(cause):
                    emit("FAIL {file}: {cause.message}")?
                    failed = failed + 1

        index = index + 1

    emit("{ran} files, {failed} failed")?
    failed | expect_equal(expected: 0)?

fn run_file(ms: String, file: String) Result[Unit, Error]:
    output := run(
        ms, ["test", file, "--json", "--timeout=30s"],
        RunOptions(timeout: 3.minutes(), max_output_bytes: 16000000)
    ).wait()?
    text := output.stdout.decode_utf8() | expect_some?
    stderr := output.stderr.decode_utf8() | expect_some?

    match check_output(output.exit_code, text):
        ok(_): return ok(unit)
        error(cause):
            emit("{text}\n{stderr}")?
            return error(cause)

fn check_output(status: Int, text: String) Result[Unit, Error]:
    status | expect_equal(expected: 0)?

    report := parse[Report](text)?
    return validate(report)

export fn main() Int:
    match run_conformance(arguments()):
        ok(_): return 0
        error(cause):
            _written := stdout().write("{cause.message}\n")
            return 1

test "reports require complete nonempty executions and count explicit skips":
    var report = Report(
        1, true, 0, [Case("pass", "passed"), Case("skip", "skipped")],
        Summary(2, 2, 1, 0, 1, 0)
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
    validate(Report(1, true, 0, [], Summary(0, 0, 0, 0, 0, 0))).is_error() | expect_true?
    check_output(1, "\{\}").is_error() | expect_true?
    check_output(0, "not JSON").is_error() | expect_true?

test "shards cover every inventory entry exactly once":
    for count in [1, 3, 4]:
        var index = 0

        while index < 179:
            var hits = 0
            var shard = 0

            while shard < count:
                if selected(index, shard, count): hits = hits + 1
                shard = shard + 1

            hits | expect_equal(expected: 1)?
            index = index + 1

fn emit(text: String) Result[Unit, Error]:
    stdout().write("{text}\n")?

test "invalid suite and shard arguments fail before running children":
    run_conformance([]).is_error() | expect_true?
    run_conformance(["ms", "unknown", "0", "1"]).is_error() | expect_true?
    run_conformance(["ms", "core", "0", "0"]).is_error() | expect_true?
    run_conformance(["ms", "core", "-1", "3"]).is_error() | expect_true?
    run_conformance(["ms", "core", "3", "3"]).is_error() | expect_true?
    run_conformance(["ms", "core", "no", "3"]).is_error() | expect_true?

test "child launch failures are returned to the fixture dispatcher":
    run_file(".", "fixture.ms").is_error() | expect_true?

test "fixture lifecycle errors invalidate an otherwise successful report":
    var report = Report(1, true, 0, [Case("pass", "passed")], Summary(1, 1, 1, 0, 0, 0))
    report.fixture_errors.append(
        FixtureError("fixture.ms", "after_all", "cleanup failed")
    )
    validate(report).is_error() | expect_true?
