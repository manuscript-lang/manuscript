# Web server and fetch client benchmarks against Go (bench/perf/web; replaces run.sh and fetch.sh). Linux only: it needs taskset, pgrep, ps, strace and /proc.
#
# Usage: ms run bench/tools/web_bench.ms -- run [SECONDS]     serves the same endpoints from Manuscript, Go and Rust and measures each
#        ms run bench/tools/web_bench.ms -- fetch [SECONDS]  Manuscript's fetch and Go's net/http client against one Go file server
# Environment: MS, GO, SERVER_CPUS (0,1), LOAD_CPUS (2,3), MS_THREADS (2). Without taskset or with fewer than 4 CPUs nothing is pinned.
import absolute, build_go, build_ms, capture, env, fail, fixed, must, platform, read_text, usage, write_text from "./lib.ms"
import Invalid, Ran, invalid from "./lib.ms"
import Stdio, arguments, commands, Subprocess from "@std/process.ms"
import copy_tree, create_directory, list, temporary from "@std/fs.ms"
import stdout from "@std/io.ms"
import milliseconds, sleep from "@std/time.ms"

fn say(text: String) Unit:
    stdout().write(text + "\n").get()

fn tail(text: String) String:
    return text.trim()

# The command line with CPU pinning when `cpus` is set.
fn pinned(cpus: String, argv: List[String]) List[String]:
    if cpus == "": return argv

    return ["taskset", "-c", cpus].concat(argv)

# Runs `argv` after raising the open-file limit, as the shell scripts did.
fn raised(argv: List[String]) Ran:
    let script = "ulimit -n 20000 2>/dev/null; exec \"$@\""
    return capture("sh", ["-c", script, "sh"].concat(argv))

# Starts `argv` with standard output in `out` and the open-file limit raised.
fn background(argv: List[String], out: String) Result[Subprocess, Invalid]:
    let script = "out=$1; shift; ulimit -n 20000 2>/dev/null; exec \"$@\" >\"$out\" 2>/dev/null"
    let args = ["-c", script, "sh", out.clone()].concat(argv)
    if let child = commands().spawn(
        "sh", args, stdin: Stdio.Null, stdout: Stdio.Null, stderr: Stdio.Null
    ):
        return ok(child)

    return invalid("cannot start {argv[0]}")

type Plan:
    w: String
    server_cpus: String
    load_cpus: String

fn plan(w: String) Plan:
    var server = env("SERVER_CPUS", "0,1")
    var load = env("LOAD_CPUS", "2,3")
    let cpus = capture("nproc", []).stdout.trim().parse_int().get(1)
    let taskset = capture("taskset", ["--version"])

    if not taskset.ok or taskset.code != 0 or cpus < 4:
        say("note: fewer than 4 CPUs or no taskset; server and load share CPUs")
        server = ""
        load = ""

    return Plan(w, server, load)

fn load_cmd(p: Plan, port: Int, args: List[String]) List[String]:
    return pinned(p.load_cpus.clone(), ["{p.w}/load/load", "{port}"].concat(args))

fn load(p: Plan, port: Int, args: List[String]) String:
    return tail(raised(load_cmd(p, port, args)).stdout)

# Whether the server answers `/health` within five seconds of starting.
fn wait_started(p: Plan, port: Int) Bool:
    for attempt in 0..50:
        let ran = raised(load_cmd(p, port, ["1", "1", "/health"]))
        if ran.ok and ran.code == 0: return true

        sleep(milliseconds(100))

    return false

fn first_pid(pattern: String) String:
    return capture("pgrep", ["-f", pattern]).stdout.split("\n")[0].trim()

# Total system calls of all threads while strace is attached for `seconds`.
fn syscalls(pid: String, seconds: Int, file: String) Int:
    let _ = capture(
        "timeout", ["{seconds}", "strace", "-f", "-c", "-p", pid, "-o", file.clone()]
    )

    for line in read_text(file).split("\n"):
        if line.contains(" total"):
            let cells = line.split(" ").filter(fn c: c != "")
            return cells[3].parse_int().get(0)

    return 0

fn rss_kb(pid: String) String:
    return capture("ps", ["-o", "rss=", "-p", pid]).stdout.trim()

fn threads(pid: String) Int:
    return list("/proc/{pid}/task").get([]).length()

fn measure_server(
    p: Plan,
    name: String,
    port: Int,
    seconds: Int,
    ms_threads: String
) Result[Unit, Invalid]:
    let data = "{p.w}/data"
    var argv = pinned(
        p.server_cpus.clone(), ["{p.w}/{name}/server", "{port}", data.clone()]
    )
    if name == "ms": argv.append(ms_threads.clone())

    var server = try background(argv, "/dev/null")

    if not wait_started(p, port):
        server.close().get(unit)
        return invalid("{name} did not start")

    let pid = first_pid("^{p.w}/{name}/server")
    for path in ["/health", "/user/42", "/top?n=10"]:
        for round in 0..2:
            say("{name} {path} {load(p, port, ["64", "{seconds}", path.clone()])}")

    if name != "rust":
        for round in 0..2:
            say("{name} io {load(p, port, ["64", "{seconds}", "/io?\{c\}"])}")

        var mixed = try background(
            load_cmd(p, port, ["32", "{seconds}", "/io?\{c\}"]), "{p.w}/mixed"
        )
        sleep(milliseconds(200))

        let during = if seconds > 1: seconds - 1 else: 1

        say("{name} health-during-io {load(p, port, ["32", "{during}", "/health"])}")
        mixed.wait().get(0)
        say("{name} io-during-health {tail(read_text("{p.w}/mixed"))}")
        mixed.close().get(unit)

    say("{name} threads {threads(pid.clone())} rss_kb {rss_kb(pid.clone())}")

    if capture("strace", ["-V"]).code == 0:
        say("{name} idle_syscalls_5s {syscalls(pid.clone(), 5, "{p.w}/idle")}")

        var busy = try background(
            [
                "timeout", "4", "strace", "-f", "-c", "-p", pid.clone(), "-o",
                "{p.w}/busy"
            ],
            "/dev/null"
        )
        sleep(milliseconds(500))

        let reqs = (
            load(p, port, ["64", "2", "/health"]).split(" ")[
                1
            ].parse_int().get(0)
            * 2
        )
        busy.wait().get(0)
        busy.close().get(unit)

        var total = 0
        for line in read_text("{p.w}/busy").split("\n"):
            if line.contains(" total"): total = line.split(" ").filter(
                fn c: c != ""
            )[3].parse_int().get(0)

        let per = if reqs > 0: total.to_float() / reqs.to_float() else: 0.0

        say(
            "{name} syscalls_per_request {fixed(per, 2)} (requests under strace {reqs})"
        )

    var idle = try background(
        pinned(
            p.load_cpus.clone(), ["{p.w}/load/load", "idle", "{port}", "10000"]
        ),
        "{p.w}/idle.out"
    )
    sleep(milliseconds(200))

    for poll in 0..120:
        if read_text("{p.w}/idle.out").contains("holding"): break

        sleep(milliseconds(500))

    say(
        "{name} idle_connections {tail(read_text("{p.w}/idle.out"))} rss_kb {rss_kb(pid.clone())}"
    )
    say("{name} /health-with-10k-idle {load(p, port, ["64", "{seconds}", "/health"])}")
    idle.close().get(unit)
    server.close().get(unit)
    return ok(unit)

fn prepare_run(here: String, w: String) Result[List[String], Invalid]:
    for dir in ["go", "ms", "load"]:
        copy_tree("{here}/{dir}", "{w}/{dir}", replace: true).get()
    create_directory("{w}/rust", recursive: true).get()
    write_text("{w}/rust/Cargo.toml", read_text("{here}/rust/Cargo.toml"))
    write_text("{w}/rust/Cargo.lock", read_text("{here}/rust/Cargo.lock"))
    copy_tree("{here}/rust/src", "{w}/rust/src", replace: true).get()
    create_directory("{w}/data", recursive: true).get()
    try build_go("{w}/go", "{w}/go/server")
    try build_go("{w}/load", "{w}/load/load")

    var names = ["ms", "go"]

    if capture("cargo", ["--version"]).code == 0:
        let ran = capture(
            "sh",
            [
                "-c",
                "cd \"$0\" && cargo build --release --locked -q && cp target/release/web-bench-rust server",
                "{w}/rust"
            ]
        )
        let _ = try must("cargo build", ran)
        names = ["ms", "go", "rust"]

    try build_ms("{w}/ms", "{w}/ms/server")
    return ok(names)

fn run_all(here: String, seconds: Int) Result[Unit, Invalid]:
    var tmp = temporary("web-bench-").get()
    let w = tmp.path()
    let names = try prepare_run(here, w)
    let p = plan(w.clone())
    var port = 18090

    for name in names:
        try measure_server(p, name, port, seconds, env("MS_THREADS", "2"))
        port += 1

    tmp.close().get(unit)
    return ok(unit)

fn cell(p: Plan, argv: List[String]) String:
    return tail(raised(pinned(p.load_cpus.clone(), argv)).stdout)

fn fetch_all(here: String, seconds: Int) Result[Unit, Invalid]:
    var tmp = temporary("web-fetch-").get()
    let w = tmp.path()
    copy_tree("{here}/fetch/go", "{w}/go", replace: true).get()
    copy_tree("{here}/fetch/ms", "{w}/ms", replace: true).get()
    create_directory("{w}/data", recursive: true).get()
    write_text("{w}/data/small", "ok\n")

    let _big = try must(
        "big",
        capture(
            "sh",
            [
                "-c", "head -c 8388608 /dev/urandom > \"$0/data/big\"", w.clone()
            ]
        )
    )
    let _text = try must(
        "text",
        capture(
            "sh",
            [
                "-c",
                "yes 'the quick brown fox jumps over the lazy dog 0123456789' | head -c 8388608 > \"$0/data/text\"",
                w.clone()
            ]
        )
    )
    try build_go("{w}/go", "{w}/go/fetch")
    try build_ms("{w}/ms", "{w}/ms/fetch")

    let p = plan(w.clone())
    var server = try background(
        pinned(
            p.server_cpus.clone(), ["{w}/go/fetch", "serve", "18950", "{w}/data"]
        ),
        "/dev/null"
    )
    sleep(milliseconds(1000))

    let fetches = [
        ["small", "1"], ["small", "8"], ["small", "64"], ["big", "1"], ["big", "8"]
    ]

    for row in fetches:
        let file = row[0].clone()
        let conns = row[1].clone()
        let url = "http://127.0.0.1:18950/{file}"
        say(
            "{file} connections={conns} go {cell(p, ["{w}/go/fetch", "get", url.clone(), conns.clone(), "{seconds}"])}"
        )
        say(
            "{file} connections={conns} ms {cell(p, ["{w}/ms/fetch", url.clone(), conns.clone(), "{seconds}"])}"
        )
        if conns == "8":
            say(
                "{file} connections={conns} ms threads=2 {cell(p, ["{w}/ms/fetch", url.clone(), conns.clone(), "{seconds}", "2"])}"
            )

    # Framings of the same 8 MiB: chunked (random) and gzip (compressible text), one connection.
    for path in ["chunked/big", "gzip/text"]:
        let url = "http://127.0.0.1:18950/{path}"
        let go = tail(
            raised(
                pinned(
                    p.load_cpus.clone(),
                    [
                        "{w}/go/fetch", "get", url.clone(), "1", "{seconds}"
                    ]
                )
            ).stdout
        )
        let ms = tail(
            raised(
                pinned(
                    p.load_cpus.clone(), ["{w}/ms/fetch", url.clone(), "1", "{seconds}"]
                )
            ).stdout
        )
        say("{path} connections=1 go {go}")
        say("{path} connections=1 ms {ms}")

    server.close().get(unit)
    tmp.close().get(unit)
    return ok(unit)

export fn main() Int:
    let args = arguments()
    if (
        args.length() < 1
        or args.length() > 2
        or (args[0] != "run" and args[0] != "fetch")
    ):
        return usage("usage: web_bench.ms -- <run|fetch> [SECONDS]")
    if platform() == "windows": return fail(
        "web_bench.ms needs Linux (taskset, pgrep, ps, strace)"
    )

    let fallback = if args[0] == "run": "5" else: "3"

    let given = if args.length() == 2: args[1].clone() else: fallback

    let seconds = given.parse_int().get(0)
    if seconds <= 0: return usage("seconds must be a positive integer")

    let here = absolute("bench/perf/web")

    let result = if args[0] == "run": run_all(here, seconds) else: fetch_all(
        here, seconds
    )

    if result.is_error(): return fail(result.err().message())

    return 0
