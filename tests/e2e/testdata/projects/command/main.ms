import (
    expect_equal from "@std/test/test.ms",
    stderr from "@std/io/io.ms",
    RunOptions, run from "@std/os/process.ms",
    stdout_bytes from "@std/io/io.ms",
)

fn exercise() Int!:
    match run(
        program: "/bin/printf",
        arguments: ["hello"],
        RunOptions(
            input: "".to_bytes(), max_output_bytes: 64, timeout: 1.seconds()
        )
    ).wait():
        error(_):
            return ok(1)
        ok(output):
            output.exit_code | try expect_equal(0)

            _ := stdout_bytes().write(value: output.stdout)
            return ok(0)

export fn main() Int:
    match exercise():
        ok(status): return status
        error(cause):
            _written := stderr().write("{cause.message}\n")
            return 1
