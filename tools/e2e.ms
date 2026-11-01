# Every fixture under tests/e2e/testdata against the Rust ms on this host (`make e2e`).
# accept/ and stdlib/ fixtures pass `ms test`; reject/ fixtures fail `ms check`. A project directory runs its
# conformance_test.ms with `ms test`; otherwise its main.ms must check, and run to expected-output.txt when that
# exists. project_check is a project whose check must fail; projects/*/reject_*.ms are reject files beside the
# modules they import. Known failures are listed in tests/e2e/expect-fail.txt (Windows-only ones in
# expect-fail.windows.txt). E2E_BUILD_TYPE picks the build type (default Release, which the deep-nesting
# fixtures need to finish quickly); E2E_JOBS the number of parallel workers.
# Usage: ms run tools/e2e.ms [-- fixture paths to run instead]
import env, exe, host, note, run_program from "./lib.ms"
import DirectoryEntry, access, list, read_file, stat from "@std/os/fs.ms"
import (
    CpuInfo,
    arguments,
    change_directory,
    working_directory,
    run,
    cpus
) from "@std/os/process.ms"
import TaskGroup, Task from "@std/concurrency/tasks.ms"
import stdout from "@std/io/io.ms"

# The exit status and combined output of one `ms` invocation.
type Ran:
    code: Int
    output: String

fn exec(ms: String, args: List[String]) Ran:
    if let out = run(ms, args):
        let text = out.stdout.decode_utf8().get("") + out.stderr.decode_utf8().get("")
        return Ran(out.exit_code, text)

    return Ran(125, "cannot start {ms}\n")

# The first lines of `output` that are not progress lines.
fn excerpt(output: String) String:
    let kept = output.split("\n").filter(
        fn l: (not l.starts_with("RUN") and not l.starts_with("PASS"))
    )
    var shown = List[String]()
    for line in kept:
        if shown.length() < 8: shown.append(line.clone())
    return shown.join("\n")

# The listed failures: fixture path to the regex of failing test names (empty for the whole fixture).
fn read_expected(files: List[String]) Map[String, String]:
    var listed = Map[String, String]()

    for file in files:
        let text = read_file(file).get().decode_utf8().get("")

        for line in text.split("\n"):
            if line.starts_with("#") or line == "": continue

            let parts = line.split("\t")

            if parts.length() > 1:
                listed.add(parts[0].clone(), parts[1].clone())
            else:
                listed.add(parts[0].clone(), "")

    return listed

type Context:
    ms: String
    build_type: String
    expected: Map[String, String]

fn base(path: String) String:
    let parts = path.split("/")
    return parts[parts.length() - 1].clone()

# The corpus replays a single-file accept/stdlib fixture under `ms test` with the same default build type when its
# frozen copy under tests/conformance/fixtures/e2e is identical, so running it here again adds nothing. A fixture
# listed as failing still runs, and so does one whose copy is tagged aliasing (the corpus run excludes those).
fn covered_by_corpus(ctx: Context, case_path: String) Bool:
    let parts = case_path.split("/")
    let twin = "tests/conformance/fixtures/e2e/{parts[parts.length() - 2]}/{parts[parts.length() - 1]}"
    if not access(twin, 0).is_ok(): return false
    if ctx.expected.contains(case_path): return false

    let lines = read_file(twin).get().decode_utf8().get("").split("\n")
    if not lines.contains("# conform: phase=test"): return false
    if lines.any(fn l: l.starts_with("# conform: tags=") and l.contains("aliasing")): return false

    let body = lines.filter(fn l: not l.starts_with("# conform:")).join("\n")
    return body == read_file(case_path).get().decode_utf8().get("")

# Whether the project's tests pass, or its main.ms checks and prints expected-output.txt.
fn project_passes(ctx: Context, dir: String) Ran:
    if access("{dir}/conformance_test.ms", 0).is_ok():
        change_directory(dir).get()

        let ran = exec(
            ctx.ms,
            [
                "test", "conformance_test.ms", "--build-type", ctx.build_type.clone()
            ]
        )
        change_directory(back(dir)).get()
        return ran

    if access("{dir}/ms.toml", 0).is_ok(): return exec(
        ctx.ms, ["check", "{dir}/ms.toml"]
    )

    let checked = exec(ctx.ms, ["check", "{dir}/main.ms"])
    if checked.code != 0: return checked
    if not access("{dir}/expected-output.txt", 0).is_ok(): return checked

    change_directory(dir).get()

    let ran = exec(ctx.ms, ["run", "main.ms", "--build-type", ctx.build_type.clone()])
    change_directory(back(dir)).get()
    if ran.code != 0: return ran

    let want = read_file("{dir}/expected-output.txt").get().decode_utf8().get("")
    if ran.output == want: return ran

    return Ran(1, "output differs from expected-output.txt\n")

# The relative path from `dir` (below the repository root) back to the root.
fn back(dir: String) String:
    return dir.split("/").map(fn _p: "..").join("/")

# Runs one fixture and returns its failure messages (empty when it passes).
fn check_fixture(ctx: Context, case_path: String) List[String]:
    var failures = List[String]()

    if case_path.contains("/projects/") and base(case_path).starts_with("reject_"):
        # A project-local reject case imports its sibling modules, so it must live beside them.
        if exec(ctx.ms, ["check", case_path.clone()]).code == 0:
            failures.append("FAIL {case_path}: a reject case_path checked clean")
    else if case_path.ends_with("/projects/project_check"):
        if project_passes(ctx, case_path).code == 0:
            failures.append("FAIL {case_path}: a reject project checked clean")
    else if case_path.contains("/projects/"):
        let ran = project_passes(ctx, case_path)
        let listed = ctx.expected.contains(case_path)

        if ran.code == 0:
            if listed: failures.append("FAIL {case_path}: listed as failing but passes")
        else if not listed:
            failures.append("FAIL {case_path}\n{excerpt(ran.output)}")
    else if case_path.contains("/reject/"):
        if exec(ctx.ms, ["check", case_path.clone()]).code == 0:
            failures.append("FAIL {case_path}: a reject case_path checked clean")
    else:
        failures = check_test_fixture(ctx, case_path)

    return failures

# An accept or stdlib fixture; a listed failure is a whole fixture, or the tests its regex names.
fn check_test_fixture(ctx: Context, case_path: String) List[String]:
    var failures = List[String]()
    let build = ctx.build_type.clone()

    if let pattern = ctx.expected.get(case_path):
        if pattern == "":
            if (
                exec(
                    ctx.ms,
                    [
                        "test", case_path.clone(), "--build-type", build
                    ]
                ).code == 0
            ):
                failures.append("FAIL {case_path}: listed as failing but passes")
            return failures

        # A missing selection also exits nonzero; it is not evidence of a failing test.
        let listing = exec(
            ctx.ms,
            [
                "test", case_path.clone(), "--build-type", build.clone(), "--list",
                "--match", pattern.clone()
            ]
        )

        if listing.code != 0:
            failures.append(
                "FAIL {case_path}: expected-failure pattern does not select runnable tests: {pattern}\n{excerpt(listing.output)}"
            )
            return failures

        let rest = exec(
            ctx.ms,
            [
                "test", case_path.clone(), "--build-type", build.clone(), "--exclude",
                pattern.clone()
            ]
        )
        if rest.code != 0:
            failures.append("FAIL {case_path}\n{excerpt(rest.output)}")
        if (
            exec(
                ctx.ms,
                [
                    "test", case_path.clone(), "--build-type", build.clone(), "--match",
                    pattern.clone()
                ]
            ).code == 0
        ):
            failures.append(
                "FAIL {case_path}: {pattern} is listed as failing but passes"
            )
        return failures

    let ran = exec(ctx.ms, ["test", case_path.clone(), "--build-type", build])
    if ran.code != 0:
        failures.append("FAIL {case_path}\n{excerpt(ran.output)}")
    return failures

fn ms_files(dir: String) List[String]:
    var names = List[String]()
    for entry in list(dir).get(List[DirectoryEntry]()):
        if entry.name.ends_with(".ms") and not entry.directory: names.append(
            "{dir}/{entry.name}"
        )
    return names.sorted(fn(a: String, b: String) Int: a.compare(b))

export fn main() Int:
    let root = working_directory().get()
    let build_type = env("E2E_BUILD_TYPE", "Release")
    var expect_files = ["tests/e2e/expect-fail.txt"]
    if host() == "windows": expect_files.append("tests/e2e/expect-fail.windows.txt")

    var code = run_program("cargo", ["xtask", "runtime"])
    if code != 0: return code

    # `ms-cli` is not rebuilt here: this tool runs on `target/debug/ms`, and Windows cannot replace an
    # executable that is running (`make e2e` and CI build it before they start the tool).
    let ctx = Context(
        "{root}/target/debug/ms{exe()}", build_type.clone(), read_expected(expect_files)
    )
    var fixtures = List[String]()
    var skipped = 0
    var projects = List[String]()
    let given = arguments()

    if given.length() > 0:
        for f in given: fixtures.append(f.clone())
    else:
        for f in ms_files("tests/e2e/testdata/accept").concat(
            ms_files("tests/e2e/testdata/stdlib")
        ):
            if covered_by_corpus(ctx, f): skipped += 1
            else: fixtures.append(f.clone())

        for f in ms_files("tests/e2e/testdata/reject"): fixtures.append(f.clone())

        for entry in list("tests/e2e/testdata/projects").get(List[DirectoryEntry]()):
            let path = "tests/e2e/testdata/projects/{entry.name}"
            projects.append(path.clone())

        for dir in projects.sorted(fn(a: String, b: String) Int: a.compare(b)):
            fixtures.append(dir.clone())
            if stat(dir.clone(), true).get().directory:
                for f in ms_files(dir):
                    if base(f).starts_with("reject_"): fixtures.append(f.clone())

    var jobs = 2

    if let n = env("E2E_JOBS", "").parse_int(): jobs = n
    else: jobs = cpus().get(List[CpuInfo]()).length()

    if jobs < 1: jobs = 1

    var count = 0
    var failed = 0
    var messages = List[String]()

    # Project fixtures change directory, which is process-wide, so they run alone after the parallel part.
    var parallel = List[String]()
    var serial = List[String]()

    for f in fixtures:
        if f.contains("/projects/") and not base(f).starts_with("reject_"): serial.append(
            f.clone()
        )
        else: parallel.append(f.clone())

    var group = TaskGroup[List[String]]()
    var tasks = List[Task[List[String], Unit, Unit]]()

    for worker in 0..jobs:
        var mine = List[String]()
        for i in 0..parallel.length():
            if (i + 1) % jobs == worker: mine.append(parallel[i].clone())

        let shared = ctx.clone()
        tasks.append(group.spawn(fn var ch: run_all(shared, mine.clone()), none))

    for i in 0..tasks.length():
        for message in tasks[i].result().get(List[String]()): messages.append(
            message.clone()
        )
    count += parallel.length()

    for f in serial:
        for message in check_fixture(ctx, f): messages.append(message.clone())
        count += 1

    for message in messages:
        note(message)
        failed += 1

    var tail = ""
    if skipped > 0: tail = ", {skipped} left to the corpus"
    (
        stdout()
        .write("e2e: {count} fixtures, {failed} failed ({build_type}){tail}\n")
        .get()
    )

    if count == 0:
        note("e2e: no fixtures ran")
        return 1

    if failed > 0: return 1

    return 0

fn run_all(ctx: Context, fixtures: List[String]) List[String]:
    var out = List[String]()
    for f in fixtures:
        for message in check_fixture(ctx, f): out.append(message.clone())
    return out
