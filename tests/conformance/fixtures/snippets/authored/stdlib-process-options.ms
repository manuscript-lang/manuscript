// conform: tags=stdlib-process,testing,tier-io
// conform: phase=test
// conform: origin=issue 2165
import expect_equal, expect_true, expect_contains from "@std/test/test.ms"
import CommandOutput, RunOptions, SpawnOptions, run, spawn from "@std/os/process.ms"
import os, Os from "@std/os/system.ms"

fn print_cwd() List[String]:
    if os() == Os.Windows:
        return ["/c", "cd"]

    return ["-c", "pwd -P"]

fn print_probe() List[String]:
    if os() == Os.Windows:
        return ["/c", "echo %MS_PROBE%"]

    return ["-c", "echo $MS_PROBE"]

fn shell() String:
    if os() == Os.Windows:
        return "cmd"

    return "sh"

fn root() String:
    if os() == Os.Windows:
        return "C:\\Windows"

    return "/"

test "run starts the child in cwd with extra environment":
    output := run(shell(), print_cwd(), RunOptions(cwd: root())).wait()?
    expect_equal(output.exit_code, 0)?
    expect_contains(output.stdout.decode_utf8().get(""), root())?

    probed := run(
        shell(), print_probe(), RunOptions(env: {"MS_PROBE": "from-env"})
    ).wait()?
    expect_contains(probed.stdout.decode_utf8().get(""), "from-env")?

test "run reports the child's peak resident set":
    output := run(shell(), print_cwd()).wait()?
    expect_true(output.max_resident_bytes > 0)?

test "spawn accepts cwd and env and reports the peak resident set after wait":
    child := spawn(
        shell(), print_probe(), SpawnOptions(env: {"MS_PROBE": "spawned"}, cwd: root())
    )?
    expect_equal(child.max_resident_bytes(), 0)?
    expect_equal((child.wait()?), 0)?
    expect_true(child.max_resident_bytes() > 0)?

test "bad cwd and variable names are rejected":
    invalid: CommandOutput! := error(Error("process: invalid input", kind: "EINVAL"))
    expect_equal(
        run(shell(), print_cwd(), RunOptions(env: {"A=B": "x"})).wait(), invalid
    )?

    missing := run(shell(), print_cwd(), RunOptions(cwd: "/definitely/not/here")).wait().err()
    expect_equal(missing.kind, "ENOENT")?
    expect_equal(
        missing.message,
        "process: not found: working directory /definitely/not/here"
    )?
