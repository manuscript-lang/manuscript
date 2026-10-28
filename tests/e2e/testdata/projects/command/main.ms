import expect_equal from "@std/test.ms"
import stderr from "@std/io.ms"
import commands from "@std/process.ms"
import stdout from "@std/io.ms"

fn exercise() Result[Int, Error]:
    match commands().run(
        program: "/bin/printf", arguments: ["hello"], input: "".to_bytes(),
        max_output_bytes: 64, timeout: 1.seconds
    ):
        error(_):
            return ok(1)
        ok(output):
            output.exit_code | try expect_equal(0)

            let _ = stdout().write_bytes(data: output.stdout)
            return ok(0)

export fn main() Int:
    match exercise():
        ok(status): return status
        error(cause):
            let _written = stderr().write("{cause.message()}\n")
            return 1
