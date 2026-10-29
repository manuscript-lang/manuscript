# conform: tags=closures,control-flow,faults,interpolation,lists,match,modules,mutation,records,stdlib-fs,stdlib-io,stdlib-json,stdlib-process,stdlib-testing,strings,testing,tier-io,try-result
# conform: phase=run
# conform: origin=scripts/conformance.ms
import {expect_equal, expect_false, expect_some, expect_true, fail} from "@std/test.ms"
import stdout from "@std/io.ms"
import arguments from "@std/process.ms"
import filesystem from "@std/fs.ms"
import commands from "@std/process.ms"
import parse from "@std/json.ms"

# Run from the repository root: ms run scripts/conformance.ms -- /absolute/path/to/ms all 0 1.
# Each source file keeps its own compiler graph, process, host roots and test report.
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
    report.format | try expect_equal(expected: 1)
    report.completed | try expect_true
    report.exit_code | try expect_equal(expected: 0)
    report.fixture_errors.is_empty() | try expect_true
    (report.summary.available > 0) | try expect_true
    report.summary.selected | try expect_equal(expected: report.summary.available)
    report.summary.failed | try expect_equal(expected: 0)
    report.summary.not_run | try expect_equal(expected: 0)
    report.tests.length() | try expect_equal(expected: report.summary.selected)
    (report.summary.passed + report.summary.skipped) | try expect_equal(
        expected: (report.summary.selected)
    )

    var passed = 0
    var skipped = 0

    for entry in report.tests:
        if entry.status == "passed":
            passed = passed + 1
        else if entry.status == "skipped":
            skipped = skipped + 1
        else:
            return fail("{entry.name}: incomplete or failed test ({entry.status})")

    passed | try expect_equal(expected: report.summary.passed)
    skipped | try expect_equal(expected: report.summary.skipped)
    return ok(unit)

fn inventory(suite: String) Result[List[String], Error]:
    let fs = filesystem()
    var files: List[String] = []

    if suite == "all" or suite == "core":
        let core = try fs.glob("tests/e2e/testdata/accept", "*.ms")
        core.is_empty() | try expect_false
        for file in core: files.append("tests/e2e/testdata/accept/{file}")

        let projects = try fs.glob(
            "tests/e2e/testdata/projects", "*/conformance_test.ms"
        )
        projects.is_empty() | try expect_false
        for file in projects: files.append("tests/e2e/testdata/projects/{file}")
        for file in [
            "examples/hello/test.ms", "examples/tooling-demo/src/math.ms",
            "pkg/tooling/format/testdata/compact.input.ms",
            "pkg/tooling/format/testdata/compact.golden.ms"
        ]:
            files.append(file)

    if suite == "all" or suite == "stdlib":
        let library = try fs.glob("tests/e2e/testdata/stdlib", "*.ms")
        library.is_empty() | try expect_false
        for file in library: files.append("tests/e2e/testdata/stdlib/{file}")

    files.is_empty() | try expect_false
    return ok(files.sorted(fn left, right: left.compare(right)))

fn selected(index: Int, shard: Int, count: Int) Bool:
    return index % count == shard

fn run(args: List[String]) Result[Unit, Error]:
    if args.length() != 4:
        return fail(
            "usage: conformance <ms executable> <all|core|stdlib> <shard> <count>"
        )

    let ms = args.get(0)
    let suite = args.get(1)
    (suite == "all" or suite == "core" or suite == "stdlib") | try expect_true

    let shard = args.get(2) | .parse_int() | try expect_some
    let count = args.get(3) | .parse_int() | try expect_some
    (count > 0 and shard >= 0 and shard < count) | try expect_true

    let files = try inventory(suite)
    var index = 0
    var failed = 0
    var ran = 0

    for file in files:
        if selected(index, shard, count):
            ran = ran + 1
            try emit("TEST {file}")

            let result = run_file(ms, file.clone())

            match result:
                ok(_): try emit("PASS {file}")
                error(cause):
                    try emit("FAIL {file}: {cause.message()}")
                    failed = failed + 1

        index = index + 1

    try emit("{ran} files, {failed} failed")
    failed | try expect_equal(expected: 0)
    return ok(unit)

fn run_file(ms: String, file: String) Result[Unit, Error]:
    let output = try commands().run(
        ms, ["test", file, "--json", "--timeout=30s"], timeout: 3.minutes,
        max_output_bytes: 16000000
    )
    let text = output.stdout.decode_utf8() | try expect_some
    let stderr = output.stderr.decode_utf8() | try expect_some

    match check_output(output.exit_code, text):
        ok(_): return ok(unit)
        error(cause):
            try emit("{text}\n{stderr}")
            return error(cause)

fn check_output(status: Int, text: String) Result[Unit, Error]:
    status | try expect_equal(expected: 0)

    let report = try parse[Report](text)
    return validate(report)

export fn main() Int:
    match run(arguments()):
        ok(_): return 0
        error(cause):
            let _written = stdout().write("{cause.message()}\n")
            return 1

test "reports require complete nonempty executions and count explicit skips":
    var report = Report(
        1, true, 0, [Case("pass", "passed"), Case("skip", "skipped")],
        Summary(2, 2, 1, 0, 1, 0)
    )
    try validate(report)
    report.completed = false
    validate(report).is_error() | try expect_true
    report.completed = true
    report.summary.not_run = 1
    validate(report).is_error() | try expect_true
    report.summary.not_run = 0
    report.tests = [Case("pass", "failed"), Case("skip", "skipped")]
    validate(report).is_error() | try expect_true
    validate(Report(1, true, 0, [], Summary(0, 0, 0, 0, 0, 0))).is_error() | try expect_true
    check_output(1, "\{\}").is_error() | try expect_true
    check_output(0, "not JSON").is_error() | try expect_true

test "shards cover every inventory entry exactly once":
    for count in [1, 3, 4]:
        var index = 0

        while index < 179:
            var hits = 0
            var shard = 0

            while shard < count:
                if selected(index, shard, count): hits = hits + 1
                shard = shard + 1

            hits | try expect_equal(expected: 1)
            index = index + 1

fn emit(text: String) Result[Unit, Error]:
    try stdout().write("{text}\n")
    return ok(unit)

test "invalid suite and shard arguments fail before running children":
    run([]).is_error() | try expect_true
    run(["ms", "unknown", "0", "1"]).is_error() | try expect_true
    run(["ms", "core", "0", "0"]).is_error() | try expect_true
    run(["ms", "core", "-1", "3"]).is_error() | try expect_true
    run(["ms", "core", "3", "3"]).is_error() | try expect_true
    run(["ms", "core", "no", "3"]).is_error() | try expect_true

test "child launch failures are returned to the fixture dispatcher":
    run_file(".", "fixture.ms").is_error() | try expect_true

test "fixture lifecycle errors invalidate an otherwise successful report":
    var report = Report(1, true, 0, [Case("pass", "passed")], Summary(1, 1, 1, 0, 0, 0))
    report.fixture_errors.append(
        FixtureError("fixture.ms", "after_all", "cleanup failed")
    )
    validate(report).is_error() | try expect_true
