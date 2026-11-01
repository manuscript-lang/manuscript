# conform: tags=stdlib-process,testing,tier-io
# conform: phase=test
# conform: origin=issue 2165
import expect_equal, expect_true, expect_contains from "@std/test/test.ms"
import run, spawn, os_type, CommandError, CommandOutput from "@std/os/process.ms"

fn print_cwd() List[String]:
    if os_type() == "windows":
        return ["/c", "cd"]

    return ["-c", "pwd -P"]

fn print_probe() List[String]:
    if os_type() == "windows":
        return ["/c", "echo %MS_PROBE%"]

    return ["-c", "echo $MS_PROBE"]

fn shell() String:
    if os_type() == "windows":
        return "cmd"

    return "sh"

fn root() String:
    if os_type() == "windows":
        return "C:\\Windows"

    return "/"

test "run starts the child in cwd with extra environment":
    let output = try run(shell(), print_cwd(), cwd: root())
    try expect_equal(output.exit_code, 0)
    try expect_contains(output.stdout.decode_utf8().get(""), root())

    let probed = try run(shell(), print_probe(), env: {"MS_PROBE": "from-env"})
    try expect_contains(probed.stdout.decode_utf8().get(""), "from-env")

test "run reports the child's peak resident set":
    let output = try run(shell(), print_cwd())
    try expect_true(output.max_resident_bytes > 0)

test "spawn accepts cwd and env and reports the peak resident set after wait":
    let child = try spawn(
        shell(), print_probe(), env: {"MS_PROBE": "spawned"}, cwd: root()
    )
    try expect_equal(child.max_resident_bytes(), 0)
    try expect_equal((try child.wait()), 0)
    try expect_true(child.max_resident_bytes() > 0)

test "bad cwd and variable names are rejected":
    let invalid: CommandOutput!CommandError = error(CommandError.InvalidInput)
    try expect_equal(run(shell(), print_cwd(), env: {"A=B": "x"}), invalid)

    let missing: CommandOutput!CommandError = error(CommandError.Unavailable)
    try expect_equal(run(shell(), print_cwd(), cwd: "/definitely/not/here"), missing)
