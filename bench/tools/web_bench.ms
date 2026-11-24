// Web server and fetch client benchmarks against Go (bench/perf/web; replaces run.sh
// and fetch.sh). Linux only: it needs taskset, pgrep, ps, strace and /proc.
//
// Usage: ms run bench/tools/web_bench.ms -- run [SECONDS] serves the same endpoints
// from Manuscript, Go and Rust and measures each
//        ms run bench/tools/web_bench.ms -- fetch [SECONDS]  Manuscript's fetch and Go's net/http client against one Go file server
// Environment: MS, GO, SERVER_CPUS (0,1), LOAD_CPUS (2,3), MS_THREADS (2). Without
// taskset or with fewer than 4 CPUs nothing is pinned.
import (
	arguments from "@std/os/env.ms",
	CopyOptions, copy, create_directory, list, temporary from "@std/os/fs.ms",
	SpawnOptions, Stdio, Subprocess, spawn from "@std/os/process.ms",
	milliseconds, sleep from "@std/time.ms",

	Ran,
	absolute,
	build_go,
	build_ms,
	capture,
	env,
	fail,
	fixed,
	invalid,
	must,
	platform,
	read_text,
	usage,
	write_text from "./lib.ms",
)

fn say(text: String) Void:
	print(text)

fn tail(text: String) String:
	return text.trim()

// The command line with CPU pinning when `cpus` is set.
fn pinned(cpus: String, argv: List[String]) List[String]:
	if cpus == "": return argv.clone()
	return ["taskset", "-c", cpus].concat(argv)

// Runs `argv` after raising the open-file limit, as the shell scripts did.
fn raised(argv: List[String]) Ran:
	script := "ulimit -n 20000 2>/dev/null; exec \"$@\""
	return capture("sh", ["-c", script, "sh"].concat(argv))

// Starts `argv` with standard output in `out` and the open-file limit raised.
fn background(argv: List[String], out: String) Subprocess!:
	script := "out=$1; shift; ulimit -n 20000 2>/dev/null; exec \"$@\" >\"$out\" 2>/dev/null"
	args := ["-c", script, "sh", out.clone()].concat(argv)
	if child := spawn(
		"sh",
		args,
		SpawnOptions(stdin: Stdio.Null, stdout: Stdio.Null, stderr: Stdio.Null),
	):
		return ok(child)

	return invalid(f"cannot start {argv[0]}")

type Plan:
	w: String
	server_cpus: String
	load_cpus: String

fn plan(w: String) Plan:
	var server = env("SERVER_CPUS", "0,1")
	var load = env("LOAD_CPUS", "2,3")
	cpus := capture("nproc", []).stdout.trim().parse_int() or 1
	taskset := capture("taskset", ["--version"])

	if not taskset.ok or taskset.code != 0 or cpus < 4:
		say("note: fewer than 4 CPUs or no taskset; server and load share CPUs")
		server = ""
		load = ""

	return Plan(w, server, load)

fn load_cmd(p: Plan, port: Int, args: List[String]) List[String]:
	return pinned(p.load_cpus.clone(), [f"{p.w}/load/load", f"{port}"].concat(args))

fn load(p: Plan, port: Int, args: List[String]) String:
	return tail(raised(load_cmd(p, port, args)).stdout)

// Whether the server answers `/health` within five seconds of starting.
fn wait_started(p: Plan, port: Int) Bool:
	for attempt in 0..50:
		ran := raised(load_cmd(p, port, ["1", "1", "/health"]))
		if ran.ok and ran.code == 0: return true

		void sleep(milliseconds(100)).wait()

	return false

fn first_pid(pattern: String) String:
	return capture("pgrep", ["-f", pattern]).stdout.split("\n")[0].trim()

// Total system calls of all threads while strace is attached for `seconds`.
fn syscalls(pid: String, seconds: Int, file: String) Int:
	void capture(
		"timeout",
		[f"{seconds}", "strace", "-f", "-c", "-p", pid, "-o", file.clone()],
	)

	for line in read_text(file).split("\n"):
		if line.contains(" total"):
			cells := line.split(" ").filter(fn c: c != "")
			return cells[3].parse_int() or 0

	return 0

fn rss_kb(pid: String) String:
	return capture("ps", ["-o", "rss=", "-p", pid]).stdout.trim()

fn threads(pid: String) Int:
	return list(f"/proc/{pid}/task").get_or([]).length()

fn measure_server(
	p: Plan,
	name: String,
	port: Int,
	seconds: Int,
	ms_threads: String,
) Void!:
	data := f"{p.w}/data"
	var argv = pinned(
		p.server_cpus.clone(),
		[f"{p.w}/{name}/server", f"{port}", data.clone()],
	)
	if name == "ms" or name == "c": argv.append(ms_threads.clone())

	var server = background(argv, "/dev/null")?

	if not wait_started(p, port):
		void server.close()
		return invalid(f"{name} did not start")

	pid := first_pid(f"^{p.w}/{name}/server")

	// The C server is the ceiling for the two tiny endpoints; it has no /top or /io.
	paths := if name == "c": ["/health", "/user/42"] else: [
		"/health", "/user/42", "/top?n=10"
	]
	for path in paths:
		for round in 0..2:
			say(f"{name} {path} {load(p, port, ["64", f"{seconds}", path.clone()])}")

	if name == "c":
		say(f"{name} threads {threads(pid.clone())} rss_kb {rss_kb(pid.clone())}")
		void server.close()
		return ok()

	if name != "rust":
		for round in 0..2:
			say(f"{name} io {load(p, port, ["64", f"{seconds}", "/io?{c}"])}")

		var mixed = background(
			load_cmd(p, port, ["32", f"{seconds}", "/io?{c}"]),
			f"{p.w}/mixed",
		)?
		void sleep(milliseconds(200)).wait()

		during := if seconds > 1: seconds - 1 else: 1
		say(f"{name} health-during-io {load(p, port, ["32", f"{during}", "/health"])}")
		mixed.wait().get_or(0)
		say(f"{name} io-during-health {tail(read_text(f"{p.w}/mixed"))}")
		void mixed.close()

	say(f"{name} threads {threads(pid.clone())} rss_kb {rss_kb(pid.clone())}")

	if capture("strace", ["-V"]).code == 0:
		say(f"{name} idle_syscalls_5s {syscalls(pid.clone(), 5, f"{p.w}/idle")}")

		var busy = background(
			[
				"timeout",
				"4",
				"strace",
				"-f",
				"-c",
				"-p",
				pid.clone(),
				"-o",
				f"{p.w}/busy",
			],
			"/dev/null",
		)?
		void sleep(milliseconds(500)).wait()

		reqs := (
			load(p, port, ["64", "2", "/health"]).split(" ")[1].parse_int()
			or 0 * 2
		)
		busy.wait().get_or(0)
		void busy.close()

		var total = 0
		for line in read_text(f"{p.w}/busy").split("\n"):
			if line.contains(" total"): total = (
				line.split(" ").filter(fn c: c != "")[3].parse_int()
				or 0
			)

		per := if reqs > 0: total.to_float() / reqs.to_float() else: 0.0
		say(
			f"{name} syscalls_per_request {fixed(per, 2)} (requests under strace {reqs})"
		)

	var idle = background(
		pinned(
			p.load_cpus.clone(),
			[f"{p.w}/load/load", "idle", f"{port}", "10000"],
		),
		f"{p.w}/idle.out",
	)?
	void sleep(milliseconds(200)).wait()

	for poll in 0..120:
		if read_text(f"{p.w}/idle.out").contains("holding"): break

		void sleep(milliseconds(500)).wait()

	say(
		f"{name} idle_connections {tail(read_text(f"{p.w}/idle.out"))} rss_kb {rss_kb(pid.clone())}"
	)
	say(
		f"{name} /health-with-10k-idle {load(p, port, ["64", f"{seconds}", "/health"])}"
	)
	void idle.close()
	void server.close()
	return ok()

fn prepare_run(here: String, w: String) List[String]!:
	for dir in ["go", "ms", "load", "c"]:
		copy(f"{here}/{dir}", f"{w}/{dir}", CopyOptions(recursive: true, replace: true)).get()
	create_directory(f"{w}/rust", recursive: true).get()
	write_text(f"{w}/rust/Cargo.toml", read_text(f"{here}/rust/Cargo.toml"))
	write_text(f"{w}/rust/Cargo.lock", read_text(f"{here}/rust/Cargo.lock"))
	copy(
		f"{here}/rust/src",
		f"{w}/rust/src",
		CopyOptions(recursive: true, replace: true),
	).get()
	create_directory(f"{w}/data", recursive: true).get()
	build_go(f"{w}/go", f"{w}/go/server")?
	build_go(f"{w}/load", f"{w}/load/load")?

	var names = ["ms", "go"]

	if capture("cargo", ["--version"]).code == 0:
		ran := capture(
			"sh",
			[
				"-c",
				"cd \"$0\" && cargo build --release --locked -q && cp target/release/web-bench-rust server",
				f"{w}/rust"
			],
		)
		void must("cargo build", ran)?
		names = ["ms", "go", "rust"]

	if capture("cc", ["--version"]).code == 0:
		ran := capture(
			"cc",
			["-O2", "-pthread", "-o", f"{w}/c/server", f"{w}/c/server.c"],
		)
		void must("cc", ran)?
		names = names.concat(["c"])

	build_ms(f"{w}/ms", f"{w}/ms/server")?
	return ok(names)

fn run_all(here: String, seconds: Int) Void!:
	var tmp = temporary("web-bench-").get()
	w := tmp.path()
	names := prepare_run(here, w)?
	p := plan(w.clone())
	var port = 18090

	for name in names:
		measure_server(p, name, port, seconds, env("MS_THREADS", "2"))?
		port += 1

	void tmp.close()

fn cell(p: Plan, argv: List[String]) String:
	return tail(raised(pinned(p.load_cpus.clone(), argv)).stdout)

fn fetch_all(here: String, seconds: Int) Void!:
	var tmp = temporary("web-fetch-").get()
	w := tmp.path()
	copy(f"{here}/fetch/go", f"{w}/go", CopyOptions(recursive: true, replace: true)).get()
	copy(f"{here}/fetch/ms", f"{w}/ms", CopyOptions(recursive: true, replace: true)).get()
	create_directory(f"{w}/data", recursive: true).get()
	write_text(f"{w}/data/small", "ok\n")

	_big := must(
		"big",
		capture(
			"sh",
			[
				"-c",
				"head -c 8388608 /dev/urandom > \"$0/data/big\"",
				w.clone(),
			],
		),
	)?
	_text := must(
		"text",
		capture(
			"sh",
			[
				"-c",
				"yes 'the quick brown fox jumps over the lazy dog 0123456789' | head -c 8388608 > \"$0/data/text\"",
				w.clone(),
			],
		),
	)?
	build_go(f"{w}/go", f"{w}/go/fetch")?
	build_ms(f"{w}/ms", f"{w}/ms/fetch")?

	p := plan(w.clone())
	var server = background(
		pinned(
			p.server_cpus.clone(),
			[f"{w}/go/fetch", "serve", "18950", f"{w}/data"],
		),
		"/dev/null",
	)?
	void sleep(milliseconds(1000)).wait()

	fetches := [
		["small", "1"],
		["small", "8"],
		["small", "64"],
		["big", "1"],
		["big", "8"],
	]

	for row in fetches:
		file := row[0].clone()
		conns := row[1].clone()
		url := f"http://127.0.0.1:18950/{file}"
		say(
			f"{file} connections={conns} go {cell(p, [f"{w}/go/fetch", "get", url.clone(), conns.clone(), f"{seconds}"])}"
		)
		say(
			f"{file} connections={conns} ms {cell(p, [f"{w}/ms/fetch", url.clone(), conns.clone(), f"{seconds}"])}"
		)
		if conns == "8":
			say(
				f"{file} connections={conns} ms threads=2 {cell(p, [f"{w}/ms/fetch", url.clone(), conns.clone(), f"{seconds}", "2"])}"
			)

	// Framings of the same 8 MiB: chunked (random) and gzip (compressible text), then a
	// redirect hop and a cookie jar round trip on small bodies, one connection.
	for path in ["chunked/big", "gzip/text", "redirect", "cookie"]:
		url := f"http://127.0.0.1:18950/{path}"
		go := tail(
			raised(
				pinned(
					p.load_cpus.clone(),
					[
						f"{w}/go/fetch",
						"get",
						url.clone(),
						"1",
						f"{seconds}",
					],
				)
			).stdout
		)
		ms := tail(
			raised(
				pinned(
					p.load_cpus.clone(),
					[
						f"{w}/ms/fetch",
						url.clone(),
						"1",
						f"{seconds}",
					],
				)
			).stdout
		)
		say(f"{path} connections=1 go {go}")
		say(f"{path} connections=1 ms {ms}")

	void server.close()
	void tmp.close()

fn main() Int:
	args := arguments()
	if (
		args.length() < 1
		or args.length() > 2
		or (args[0] != "run" and args[0] != "fetch")
	):
		return usage("usage: web_bench.ms -- <run|fetch> [SECONDS]")
	if platform() == "windows": return fail(
		"web_bench.ms needs Linux (taskset, pgrep, ps, strace)"
	)

	fallback := if args[0] == "run": "5" else: "3"
	given := if args.length() == 2: args[1].clone() else: fallback
	seconds := given.parse_int() or 0
	if seconds <= 0: return usage("seconds must be a positive integer")

	here := absolute("bench/perf/web")
	result := if args[0] == "run": run_all(here, seconds) else: fetch_all(here, seconds)
	if result.is_error(): return fail(result.err().message)

	return 0
