# The frozen conformance corpus against the Rust ms on this host (`make conform`).
# Known failures: tests/conformance/expect-fail.txt plus expect-fail.<os>.txt when present.
# CONFORM_SHARD=i/n splits the run. Arguments after `--` go to `ms-conform run`.
# Usage: ms run tools/conform.ms [-- extra ms-conform run arguments]
import env, exe, host, run from "./lib.ms"
import access, create_directory, read_file, write_file from "@std/fs.ms"
import arguments from "@std/process.ms"

export fn main() Int:
    var code = run("cargo", ["xtask", "runtime"])
    if code != 0: return code

    code = run(
        "cargo",
        [
            "build", "--locked", "-q", "-p", "ms-cli", "-p", "ms-conform",
            "--target-dir", "target"
        ]
    )
    if code != 0: return code

    create_directory(".artifacts", recursive: true).get()

    let allow = ".artifacts/conform-expect-fail.txt"
    var text = (
        read_file("tests/conformance/expect-fail.txt")
        .get()
        .decode_utf8()
        .get("")
    )
    let host_list = "tests/conformance/expect-fail.{host()}.txt"
    if access(host_list, 0).is_ok():
        text = text + read_file(host_list).get().decode_utf8().get("")
    write_file(allow, text, replace: true).get()

    let conform = "target/debug/ms-conform{exe()}"
    let ms = "target/debug/ms{exe()}"
    let shard = env("CONFORM_SHARD", "0/1")
    code = run(conform, ["lint"])
    if code != 0: return code

    let extra = arguments()
    let main_run = [
        "run", "--ms", ms.clone(), "--phase", "run,check,test", "--exclude-tag",
        "aliasing", "--expect-fail", allow.clone(), "--strict", "--shard",
        shard.clone(), "--quiet", "--markdown", ".artifacts/conform.md"
    ]
    code = run(conform, main_run.concat(extra.clone()))
    if code != 0: return code

    # Parsing and formatting do not depend on aliasing, so the parse phase replays every fixture.
    let parse_run = [
        "run", "--ms", ms.clone(), "--phase", "parse", "--expect-fail", allow.clone(),
        "--strict", "--shard", shard.clone(), "--quiet", "--markdown",
        ".artifacts/conform-parse.md"
    ]
    return run(conform, parse_run.concat(extra))
