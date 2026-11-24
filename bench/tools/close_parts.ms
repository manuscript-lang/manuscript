// Proves that closing what containers and fields own costs nothing when no element is a
// resource: every benchmark project under bench/perf is lowered by a compiler from
// before the change (BASE) and one with it (HEAD), and the lowered MIR (`ms emit`) and
// the linked binaries must be byte for byte the same. Prints one line per project and
// exits 1 on a difference. Usage: ms run bench/tools/close_parts.ms -- BASE_MS HEAD_MS
import (
	arguments from "@std/os/env.ms",
	CopyOptions,
	GlobOptions,
	copy,
	glob,
	read_file,
	remove,
	temporary from "@std/os/fs.ms",

	absolute, run_in, usage from "./lib.ms",
)

fn same_bytes(a String, b String) Bool:
	left := read_file(a).wait()
	right := read_file(b).wait()
	if left.is_error() or right.is_error(): return false

	return left.get_or("".to_bytes()) == right.get_or("".to_bytes())

fn ok_status(program String, args List[String], dir String) Bool:
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
	projects := glob("bench/perf", GlobOptions(patterns: ["**/ms.toml"])).get_or(
		[]
	).map(fn e: e.path.clone())

	for toml in projects.sorted():
		dir := ("bench/perf/" + toml.slice(0, toml.length() - "ms.toml".length()))
		name := dir.slice("bench/perf/".length(), dir.length() - 1)

		// Both compilers build the same directory, so no path differs between the
		// outputs.
		void remove(f"{w}/p", recursive: true)
		copy(dir, f"{w}/p", CopyOptions(recursive: true, replace: true)).get()
		void remove(f"{w}/p/ms.lock")

		lowers := (
			ok_status(
				base,
				["emit", "ms.toml", "-o", f"{w}/a.mir"],
				f"{w}/p",
			)
			and ok_status(
				head,
				["emit", "ms.toml", "-o", f"{w}/b.mir"],
				f"{w}/p",
			)
		)

		if not lowers:
			print(f"skip   {name} (does not lower)")
			skipped += 1
			continue

		void remove(f"{w}/p/ms.lock")

		_a := ok_status(base, ["build", "ms.toml", "-o", f"{w}/a.bin"], f"{w}/p")
		void remove(f"{w}/p/ms.lock")

		_b := ok_status(head, ["build", "ms.toml", "-o", f"{w}/b.bin"], f"{w}/p")

		if (
			same_bytes(f"{w}/a.mir", f"{w}/b.mir")
			and same_bytes(f"{w}/a.bin", f"{w}/b.bin")
		):
			print(f"same   {name}")
			same += 1
		else:
			print(f"DIFFER {name}")
			differ += 1

	print(f"{same} identical, {differ} different, {skipped} skipped")
	return if differ == 0: 0 else: 1
