# Leak sweep (`make leak-check`): runs the programs of the conformance corpus that finish normally against a runtime
# built with allocation counters (`ms-rt` feature `stats`), which prints the count of live heap blocks at exit. A
# correct program frees everything it allocated, so any nonzero count is a leak. Faulting and rejected programs print
# no count and are skipped. Arguments name the files to sweep instead.
# MS names the ms that runs the programs (default target/release/ms).
# Usage: ms run tools/leak-check.ms [-- files]
import tool_ms, use_stats_runtime from "./lib.ms"
import glob, read_file, temporary from "@std/os/fs.ms"
import arguments, change_directory, working_directory, run from "@std/os/process.ms"
import seconds from "@std/os/time.ms"
import stdout from "@std/io/io.ms"

# The live block counts the runtime printed on standard error; a program that starts child
# processes prints one per process, and their sum is what leaked. Empty when none was printed.
fn live_blocks(text: String) List[Int]:
    var counts = List[Int]()
    for line in text.split("\n"):
        if line.starts_with("ms-rt live blocks at exit: "):
            if let n = line.slice(27, line.length()).get("").trim().parse_int(): counts.append(
                n
            )
    return counts

export fn main() Int:
    let code = use_stats_runtime()
    if code != 0: return code

    let root = working_directory().get()
    var files = List[String]()
    for f in arguments(): files.append(f.clone())

    if files.length() == 0:
        for dir in [
            "tests/conformance/fixtures/fuzz/run", "tests/conformance/fixtures/e2e",
            "tests/conformance/fixtures/examples"
        ]:
            for f in glob(dir, "**/*.ms").get(List[String]()):
                let path = "{dir}/{f}"
                if read_file(path.clone()).get().decode_utf8().get(
                    ""
                ).contains("fn main"): files.append(path.clone())

    let ms = tool_ms(root.clone())
    let scratch = temporary("ms-leak-").get()
    change_directory(scratch.path()).get()

    var swept = 0
    var leaks = 0

    for f in files:
        let absolute = "{root}/{f}"

        if let out = run(ms.clone(), ["run", absolute.clone()], timeout: seconds(60)):
            let counts = live_blocks(out.stderr.decode_utf8().get(""))
            if counts.length() == 0: continue

            swept += 1

            let total = counts.fold(0, fn(a: Int, b: Int) Int: a + b)

            if total != 0:
                leaks += 1
                stdout().write("leak: {absolute} left {total} live blocks\n").get()

    change_directory(root).get()
    stdout().write("swept {swept} programs, {leaks} leaking\n").get()

    if swept == 0:
        stdout().write("no program reported a live block count\n").get()
        return 1

    if leaks > 0: return 1

    return 0
