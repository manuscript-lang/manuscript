// Copy sweep (`make copy-check`): builds the programs and test fixtures of the corpus with
// `MS_COPY_PROBE=1`, which makes the compiler print every implicit `copy` of an object value (a
// closure, interface or runtime object, or a value holding one) in the lowered code. Such a
// value has one owner and a program duplicates it only through a written `.clone()`, which the
// probe leaves out, so each line is a lowering site to fix; the sweep fails while any remain.
// Arguments name the files to sweep instead.
// MS names the ms that builds the programs (default target/release/ms).
// Usage: ms run tools/copy-check.ms [-- files]
import tool_ms from "./lib.ms"
import glob, GlobOptions, read_file, temporary from "@std/os/fs.ms"
import RunOptions, run from "@std/os/process.ms"
import arguments, change_directory, working_directory from "@std/os/env.ms"
import seconds from "@std/time.ms"
import stdout from "@std/io/io.ms"

// The probe lines the compiler printed on standard error, without their prefix.
fn copies(text: String) List[String]:
    var sites = List[String]()
    for line in text.split("\n"):
        if line.starts_with("copy-probe\t"): sites.append(
            line.slice(11, line.length()).get("")
        )
    return sites

export fn main() Int:
    let root = working_directory().get()
    var files = List[String]()
    for f in arguments(): files.append(f.clone())
    if files.length() == 0:
        for dir in [
            "tests/conformance/fixtures/e2e", "tests/conformance/fixtures/examples",
            "tests/e2e/testdata/accept", "tests/e2e/testdata/stdlib",
            "tests/ownership-counts"
        ]:
            for f in glob(dir, GlobOptions(patterns: ["**/*.ms"])).get([]):
                files.append("{dir}/{f.path}")

    let ms = tool_ms(root.clone())
    let scratch = temporary("ms-copy-").get()
    let binary = "{scratch.path()}/program"
    var env = Map[String, String]()
    env.add("MS_COPY_PROBE", "1")
    env.add("MS_CACHE", "off")

    var swept = 0
    var total = 0
    var failing = 0

    for f in files:
        let absolute = "{root}/{f}"
        let source = read_file(absolute.clone()).wait().get().decode_utf8().get("")
        var command = List[String]()

        if source.contains("export fn main"):
            command = ["build", absolute.clone(), "-o", binary.clone()]
        else if source.contains("\ntest "):
            command = ["test", absolute.clone(), "--match", "no test is selected"]
        else:
            continue

        if let out = run(
            ms.clone(), command, RunOptions(timeout: seconds(120), env: env.clone())
        ).wait():
            swept += 1

            let sites = copies(out.stderr.decode_utf8().get(""))
            if sites.length() == 0: continue

            failing += 1
            total += sites.length()
            for site in sites: stdout().write("copy: {f}\t{site}\n").get()

    change_directory(root).get()
    print("swept {swept} programs, {total} object copies in {failing}")

    if swept == 0:
        print("no program was built")
        return 1

    if total != 0: return 1

    return 0
