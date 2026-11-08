// Cancellation sweep (`make cancel-sweep`): cancels each test of the e2e fixtures at every park
// (await point) in turn and checks that nothing leaks. A counting runtime (`ms-rt` feature `stats`)
// numbers the parks of a process; `MS_PARK_COUNT=1` prints how many a test made, and
// `MS_CANCEL_AT_PARK=k` makes the k-th one report a cancellation, as if the parking task had been
// cancelled there. The cancelled test must end with the same live blocks as the uncancelled run (a test that leaks without cancellation belongs to `leak-check`). A run that ends with more Rust heap blocks (`ms-rt rust heap at exit`) is listed as `heap:` but does not fail the sweep: a cancelled test also keeps its failure report, so each hit needs a look. Arguments name the
// files to sweep (default: tests/e2e/testdata/stdlib). SWEEP_MAX_PARKS bounds the parks tried per
// test (default 64); MS names the ms to run (default target/release/ms).
// Usage: ms run tools/cancel-sweep.ms [-- files]
import env, tool_ms, use_stats_runtime from "./lib.ms"
import glob, GlobOptions, read_file, temporary from "@std/os/fs.ms"
import RunOptions, run from "@std/os/process.ms"
import arguments, change_directory, working_directory from "@std/os/env.ms"
import system_info from "@std/os/system.ms"
import Promise, promise from "@std/concurrency/promise.ms"
import seconds from "@std/time.ms"
import stdout from "@std/io/io.ms"

// One test's counts as the runtime printed them.
type Counted:
    name: String
    parks: Int
    heap: Int
    live: Int

// The tests of one `ms test` run with the parks they made and the blocks left live: each test
// prints RUN before it starts, then the runtime prints both counts as it ends.
fn counted(text: String) List[Counted]:
    var found = List[Counted]()
    var name = ""
    var parks = 0
    var heap = 0

    for line in text.split("\n"):
        if line.starts_with("RUN "): name = line.slice(4, line.length()).get("")
        else if line.starts_with("ms-rt parks: "):
            parks = line.slice(13, line.length()).get("").trim().parse_int().get(0)
        else if line.starts_with("ms-rt rust heap at exit: blocks="):
            heap = line.slice(
                32, line.length()
            ).get("").split(" ")[0].parse_int().get(0)
        else if line.starts_with("ms-rt live blocks at exit: "):
            let live = line.slice(27, line.length()).get("").trim().parse_int().get(0)
            found.append(
                Counted(
                    name: name.clone(), parks: parks, heap: heap, live: live
                )
            )

    return found

fn has_tests(source: String) Bool:
    return source.starts_with("test \"") or source.contains("\ntest \"")

fn test_run(ms: String, file: String, filter: String, cancel_at: Int) List[Counted]:
    var settings = Map[String, String]()
    settings["MS_PARK_COUNT"] = "1"
    if cancel_at > 0: settings["MS_CANCEL_AT_PARK"] = "{cancel_at}"

    var arguments = ["test", file.clone()]
    if filter != "": arguments = arguments.concat(["--filter", filter.clone()])
    if let out = run(
        ms.clone(), arguments, RunOptions(timeout: seconds(120), env: settings)
    ).wait(): return counted(
        out.stdout.decode_utf8().get("") + out.stderr.decode_utf8().get("")
    )

    return List[Counted]()

// Sweeps `files`: one line per cancelled run (`swept`), then one `leak:` report per run that
// left live blocks.
fn sweep(ms: String, root: String, files: List[String], most: Int) List[String]:
    var lines = List[String]()

    for f in files:
        let file = "{root}/{f}"

        for base in test_run(ms.clone(), file.clone(), "", 0):
            if base.parks == 0: continue

            let last = if base.parks < most: base.parks else: most

            for k in 1..last + 1:
                for hit in test_run(ms.clone(), file.clone(), base.name.clone(), k):
                    lines.append("swept")

                    if hit.live != base.live: lines.append(
                        "leak: {f} \"{hit.name}\" cancelled at park {k} of {base.parks} left {hit.live} live blocks (uncancelled run: {base.live})"
                    )
                    else if hit.heap > base.heap: lines.append(
                        "heap: {f} \"{hit.name}\" cancelled at park {k} of {base.parks} ended with {hit.heap} Rust heap blocks (uncancelled run: {base.heap})"
                    )

    return lines

export fn main() Int:
    let code = use_stats_runtime()
    if code != 0: return code

    let root = working_directory().get()
    var files = List[String]()
    for f in arguments(): files.append(f.clone())

    if files.length() == 0:
        for f in glob("tests/e2e/testdata/stdlib", GlobOptions(patterns: ["*.ms"])).get(
            []
        ):
            let path = "tests/e2e/testdata/stdlib/{f.path}"
            if has_tests(read_file(path.clone()).wait().get().decode_utf8().get("")): files.append(
                path.clone()
            )

    let ms = tool_ms(root.clone())
    let scratch = temporary("ms-cancel-").get()
    change_directory(scratch.path()).get()

    var jobs = system_info().cpu_count
    if let n = env("LEAK_JOBS", "").parse_int(): jobs = n
    if jobs < 1: jobs = 1

    var most = 64
    if let n = env("SWEEP_MAX_PARKS", "").parse_int(): most = n

    var chunks = List[List[String]]()

    for worker in 0..jobs:
        var mine = List[String]()
        for i in 0..files.length():
            if i % jobs == worker: mine.append(files[i].clone())
        chunks.append(mine)

    var tasks = List[Promise[List[String]]]()
    for worker in 0..jobs:
        tasks.append(
            promise(
                fn: ok(
                    sweep(
                        ms.clone(), root.clone(), chunks[worker], most
                    )
                )
            )
        )

    var swept = 0
    var leaks = 0
    var heaps = 0

    for task in tasks:
        for line in task.wait().get(List[String]()):
            if line == "swept": swept += 1
            else:
                if line.starts_with("heap: "): heaps += 1
                else: leaks += 1

                stdout().write("{line}\n").get()

    change_directory(root).get()
    (
        stdout()
        .write(
            "cancel-sweep: {swept} cancelled runs, {leaks} leaking, {heaps} with extra Rust heap\n"
        )
        .get()
    )
    if leaks > 0: return 1

    return 0
