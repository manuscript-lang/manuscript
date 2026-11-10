// Proves that closing what containers and fields own costs nothing when no element is a resource: every benchmark project under
// bench/perf is lowered by a compiler from before the change (BASE) and one with it (HEAD), and the lowered MIR (`ms emit`) and
// the linked binaries must be byte for byte the same. Prints one line per project and exits 1 on a difference.
// Usage: ms run bench/tools/close_parts.ms -- BASE_MS HEAD_MS
import (
	absolute, run_in, usage from "./lib.ms",
	copy,
	CopyOptions,
	glob,
	GlobOptions,
	read_file,
	remove,
	temporary from "@std/os/fs.ms",
	arguments from "@std/os/env.ms",
)

fn same_bytes(a: String, b: String) Bool:
	left := read_file(a).wait()
	right := read_file(b).wait()
	if left.is_error() or right.is_error(): return false

	return left.get("".to_bytes()) == right.get("".to_bytes())

fn ok_status(program: String, args: List[String], dir: String) Bool:
	ran := run_in(dir, program, args)
	return ran.ok and ran.code == 0

fn main() Int:
	args := arguments()
	if args.length() != 2: return usage("usage: close_parts.ms -- BASE_MS HEAD_MS")

	base := absolute(args[0].clone())
	head := absolute(args[1].clone())
	tmp := temporary("close-parts-").get()
	w := tmp.path()
	var same = 0
	var differ = 0
	var skipped = 0
	projects := glob("bench/perf", GlobOptions(patterns: ["**/ms.toml"])).get([]).map(
		fn e: e.path.clone()
	)

	for toml in projects.sorted():
		dir := (
			"bench/perf/"
			+ toml.slice(0, toml.length() - "ms.toml".length()).get("")
		)
		name := dir.slice("bench/perf/".length(), dir.length() - 1).get("")

		// Both compilers build the same directory, so no path differs between the outputs.
		remove("{w}/p", recursive: true).get(unit)
		copy(dir, "{w}/p", CopyOptions(recursive: true, replace: true)).get()
		remove("{w}/p/ms.lock").get(unit)

		lowers := (
			ok_status(base, ["emit", "ms.toml", "-o", "{w}/a.mir"], "{w}/p")
			and ok_status(
				head, ["emit", "ms.toml", "-o", "{w}/b.mir"], "{w}/p"
			)
		)

		if not lowers:
			print("skip   {name} (does not lower)")
			skipped += 1
			continue

		remove("{w}/p/ms.lock").get(unit)

		_a := ok_status(base, ["build", "ms.toml", "-o", "{w}/a.bin"], "{w}/p")
		remove("{w}/p/ms.lock").get(unit)

		_b := ok_status(head, ["build", "ms.toml", "-o", "{w}/b.bin"], "{w}/p")

		if (
			same_bytes("{w}/a.mir", "{w}/b.mir")
			and same_bytes("{w}/a.bin", "{w}/b.bin")
		):
			print("same   {name}")
			same += 1
		else:
			print("DIFFER {name}")
			differ += 1

	print("{same} identical, {differ} different, {skipped} skipped")
	return if differ == 0: 0 else: 1
