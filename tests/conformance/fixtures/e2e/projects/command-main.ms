# conform: tags=diagnostics,interpolation,match,modules,stdlib-io,stdlib-process,stdlib-testing,tier-io,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/command/main.ms
from "@std/test.ms" import expect_equal
from "@std/io.ms" import stderr
from "@std/process.ms" import commands
from "@std/io.ms" import stdout

def exercise() -> Result[Int, Error]:
    match commands().run(
        program: "/bin/printf", arguments: ["hello"], input: "".to_bytes(),
        max_output_bytes: 64, timeout: 1.seconds
    ):
        case error(_):
            return ok(1)
        case ok(output):
            output.exit_code | try expect_equal(0)
            stdout().write_bytes(data: output.stdout)
            return ok(0)

export def main() -> Int:
    match exercise():
        case ok(status): return status
        case error(cause):
            let written = stderr().write(f"{cause.message()}\n")
            return 1
