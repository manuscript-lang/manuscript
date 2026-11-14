// Times file, directory, process and pipe operations so Linux, macOS and Windows can be
// compared on one run (the `Platform benchmarks` workflow). Usage:
// `ms run bench/tools/platform_io.ms [-- files]`; MS names the `ms` binary. Prints one
// line per measurement, nanoseconds per operation, min of three rounds.
import (
	Bytes from "@std/bytes.ms",
	stdin, stdout_bytes from "@std/io/io.ms",
	min from "@std/math/math.ms",
	arguments from "@std/os/env.ms",
	create_directory,
	list,
	read_file,
	remove,
	rename,
	temporary_directory,
	write_file from "@std/os/fs.ms",
	RunOptions, SpawnOptions, run, spawn from "@std/os/process.ms",

	capture, exe, fail, host, ms_binary, now_ns, usage from "./lib.ms",
)

// The child of the pipe round trip: echoes every chunk it reads.
ECHO := "import stdin, stdout_bytes from \"@std/io/io.ms\"\n\nfn main() Unit:\n\tvar input = stdin()\n\tvar output = stdout_bytes()\n\twhile true:\n\t\tchunk := input.next().get()\n\t\tif data := chunk:\n\t\t\toutput.write(data).get()\n\t\telse:\n\t\t\treturn\n"

fn report(name: String, best_ns: Int, ops: Int) Unit:
	print("{host()} {name} {best_ns / ops} ns/op ({ops} ops)")

fn write_files(dir: String, n: Int) Unit!:
	for i in 0..n:
		write_file("{dir}/f{i}.txt", "file {i}\n", true).wait()?

fn read_files(dir: String, n: Int) Int!:
	var total = 0

	for i in 0..n:
		data := read_file("{dir}/f{i}.txt").wait()?
		total += data.length()

	return ok(total)

fn rename_files(dir: String, n: Int) Unit!:
	for i in 0..n:
		rename("{dir}/f{i}.txt", "{dir}/g{i}.txt")?

fn walk(dir: String) Int!:
	var found = 0

	for entry in list(dir)?:
		found += 1
		if entry.directory:
			found += walk("{dir}/{entry.name}")?

	return ok(found)

fn files(n: Int) Unit!:
	root := temporary_directory("platform-io")?
	var best_write = 1000000000000
	var best_read = best_write
	var best_rename = best_write
	var best_walk = best_write

	for round in 0..3:
		dir := "{root}/r{round}"
		create_directory("{dir}/sub", true)?

		start := now_ns()
		write_files(dir, n)?
		best_write = min(best_write, now_ns() - start)

		start2 := now_ns()
		_ := read_files(dir, n)?
		best_read = min(best_read, now_ns() - start2)

		start3 := now_ns()
		rename_files(dir, n)?
		best_rename = min(best_rename, now_ns() - start3)

		start4 := now_ns()
		_ := walk(root)?
		best_walk = min(best_walk, now_ns() - start4)

	report("write_file", best_write, n)
	report("read_file", best_read, n)
	report("rename", best_rename, n)
	report("walk entry", best_walk, n)
	remove(root, true)?

fn spawns(program: String, n: Int) Unit!:
	var best = 1000000000000

	for round in 0..3:
		start := now_ns()
		for i in 0..n:
			_done := run(program, ["--version"]).wait()?
		best = min(best, now_ns() - start)

	report("spawn and wait", best, n)

// One request and reply over a child's stdin and stdout, `n` times.
fn round_trips(program: String, n: Int) Unit!:
	var child = spawn(program, [], SpawnOptions())?
	var input = child.stdin()
	var output = child.stdout()
	print("{host()} pipe round trip: child started")

	var best = 1000000000000

	for round in 0..3:
		start := now_ns()

		for i in 0..n:
			input.write("ping\n".to_bytes())?
			input.flush()?

			_reply := output.next()?
			if round == 0 and i == 0:
				print("{host()} pipe round trip: first reply")

		best = min(best, now_ns() - start)

	report("pipe round trip", best, n)
	child.kill()

	_ := child.wait()

fn run_all(n: Int) Unit!:
	files(n)?
	spawns(ms_binary(), 30)?

	work := temporary_directory("platform-io-echo")?
	write_file("{work}/echo.ms", ECHO).wait()?

	built := capture(
		ms_binary(),
		["build", "{work}/echo.ms", "-o", "{work}/echo{exe()}"],
	)

	if built.ok and built.code == 0:
		round_trips("{work}/echo{exe()}", 300)?
	else:
		print("{host()} pipe round trip skipped: {built.stderr}")

	remove(work, true)?

fn main() Int:
	var n = 2000
	args := arguments()

	if args.length() > 1:
		if parsed := args[1].parse_int(): n = parsed
		else: return usage("usage: platform_io.ms [-- files]")

	done := run_all(n)
	if done.is_error(): return fail("platform_io: {done.err().message}")

	return 0
