# Proves that closing what containers and fields own costs nothing when no element is a resource: every benchmark project under
# bench/perf is lowered by a compiler from before the change (BASE) and one with it (HEAD), and the lowered MIR (`ms emit`) and
# the linked binaries must be byte for byte the same. Prints one line per project and exits 1 on a difference.
# Usage: ms run bench/tools/close_parts.ms -- BASE_MS HEAD_MS
import absolute, run_in, usage from "./lib.ms"
import copy_tree, glob, read_file, remove, temporary from "@std/fs.ms"
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"

fn same_bytes(a: String, b: String) Bool:
    let left = read_file(a)
    let right = read_file(b)
    if left.is_error() or right.is_error(): return false

    return left.get("".to_bytes()) == right.get("".to_bytes())

fn ok_status(program: String, args: List[String], dir: String) Bool:
    let ran = run_in(dir, program, args)
    return ran.ok and ran.code == 0

export fn main() Int:
    let args = arguments()
    if args.length() != 2: return usage("usage: close_parts.ms -- BASE_MS HEAD_MS")

    let base = absolute(args[0].clone())
    let head = absolute(args[1].clone())
    let tmp = temporary("close-parts-").get()
    let w = tmp.path()
    var same = 0
    var differ = 0
    var skipped = 0
    let projects = glob("bench/perf", "**/ms.toml", max_entries: none).get([])

    for toml in projects.sorted():
        let dir = (
            "bench/perf/"
            + toml.slice(0, toml.length() - "ms.toml".length()).get("")
        )
        let name = dir.slice("bench/perf/".length(), dir.length() - 1).get("")

        # Both compilers build the same directory, so no path differs between the outputs.
        remove("{w}/p", recursive: true).get(unit)
        copy_tree(dir, "{w}/p", replace: true).get()
        remove("{w}/p/ms.lock").get(unit)

        let lowers = (
            ok_status(base, ["emit", "ms.toml", "-o", "{w}/a.mir"], "{w}/p")
            and ok_status(
                head, ["emit", "ms.toml", "-o", "{w}/b.mir"], "{w}/p"
            )
        )

        if not lowers:
            stdout().write("skip   {name} (does not lower)\n").get()
            skipped += 1
            continue

        remove("{w}/p/ms.lock").get(unit)

        let _a = ok_status(base, ["build", "ms.toml", "-o", "{w}/a.bin"], "{w}/p")
        remove("{w}/p/ms.lock").get(unit)

        let _b = ok_status(head, ["build", "ms.toml", "-o", "{w}/b.bin"], "{w}/p")

        if (
            same_bytes("{w}/a.mir", "{w}/b.mir")
            and same_bytes("{w}/a.bin", "{w}/b.bin")
        ):
            stdout().write("same   {name}\n").get()
            same += 1
        else:
            stdout().write("DIFFER {name}\n").get()
            differ += 1

    stdout().write("{same} identical, {differ} different, {skipped} skipped\n").get()

    return if differ == 0: 0 else: 1
