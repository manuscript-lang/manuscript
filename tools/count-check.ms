# Ownership count gate (`make count-check`): runs the programs of tests/ownership-counts in Debug and Release against
# a runtime built with counters (`ms-rt` feature `stats`) and compares what they report with the `# expect-debug:` and
# `# expect-release:` headers (`key=value` pairs from the runtime's "ms-rt counts:" line; absent keys are not checked)
# and `# expect-stdout:` lines (the program's stdout, in order, on both). Cleanup order is the stdout lines.
# A change may not raise a count without a stated reason; update the header in the same change.
# MS names the ms that runs the programs (default target/release/ms).
# Usage: ms run tools/count-check.ms [-- files]
import tool_ms, use_stats_runtime from "./lib.ms"
import glob, read_file, temporary from "@std/os/fs.ms"
import arguments, change_directory, working_directory, run from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

# The text after `prefix` on every line that starts with it.
fn after(text: String, prefix: String) List[String]:
    var found = List[String]()
    for line in text.split("\n"):
        if line.starts_with(prefix): found.append(
            line.slice(prefix.length(), line.length()).get("")
        )
    return found

export fn main() Int:
    let code = use_stats_runtime()
    if code != 0: return code

    let root = working_directory().get()
    var files = List[String]()
    for f in arguments(): files.append(f.clone())
    if files.length() == 0:
        for f in glob("tests/ownership-counts", "*.ms").get(List[String]()): files.append(
            "tests/ownership-counts/{f}"
        )

    let ms = tool_ms(root.clone())
    let scratch = temporary("ms-counts-").get()
    change_directory(scratch.path()).get()

    var failures = 0
    var checked = 0

    for f in files:
        let source = read_file("{root}/{f}").get().decode_utf8().get("")
        let expected_out = after(source, "# expect-stdout: ")

        for build in ["debug", "release"]:
            var out = ""
            var err = ""

            if let ran = run(
                ms.clone(), ["run", "{root}/{f}", "--build-type", build.clone()]
            ):
                out = ran.stdout.decode_utf8().get("")
                err = ran.stderr.decode_utf8().get("")

            let counts = after(err, "ms-rt counts: ")
            let live = after(err, "ms-rt live blocks at exit: ")
            checked += 1

            if live.length() == 0 or live[0] != "0":
                failures += 1

                var shown = "an unreported number of"
                if live.length() > 0: shown = live[0].clone()
                stdout().write("leak: {f} ({build}) left {shown} live blocks\n").get()

            var have = List[String]()
            if counts.length() > 0: have = counts[0].split(" ")

            for header in after(source, "# expect-{build}: "):
                for pair in header.split(" "):
                    if pair == "": continue

                    checked += 1

                    let want = pair.clone()

                    if not have.contains(want):
                        failures += 1
                        (
                            stdout()
                            .write(
                                "count: {f} ({build}) wants {want}; runtime reported: {counts.join(" ")}\n"
                            )
                            .get()
                        )

            if expected_out.length() > 0:
                checked += 1

                if out.trim_end() != expected_out.join("\n"):
                    failures += 1
                    stdout().write("stdout: {f} ({build}) differs:\n{out}\n").get()

    change_directory(root).get()
    stdout().write("checked {checked} expectations, {failures} failing\n").get()

    if checked == 0:
        stdout().write("no expectations ran\n").get()
        return 1

    if failures > 0: return 1

    return 0
