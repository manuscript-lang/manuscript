from "@std/process.ms" import Command, CommandError, CommandOutput
from "@std/testing.ms" import expect_equal

test "command keeps each argument as one item":
    var command = Command("git")
    command.arg("log")
    command.arg("--format=%h; rm -rf /")
    command.args(["a b", "$HOME"])
    try expect_equal(
        command.arguments, ["log", "--format=%h; rm -rf /", "a b", "$HOME"]
    )

test "command run rejects an empty program":
    let command = Command("")
    let result = command.run()
    let invalid: Result[CommandOutput, CommandError] = error(CommandError.InvalidInput)
    try expect_equal(result, invalid)
