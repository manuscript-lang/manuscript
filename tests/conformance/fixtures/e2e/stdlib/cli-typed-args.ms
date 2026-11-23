// conform: tags=testing,tier-stdlib,cli
// conform: phase=test
import (
	Arg, Command, FlagKind, command from "@std/cli/command.ms",
	expect_contains,
	expect_equal,
	expect_error,
	expect_ok,
	fail from "@std/test/test.ms",
)

type DoneOptions:
	id: Int
	weight: Float

fn done_command() Command:
	return Command(
		name: "todo",
		children: [
			command[DoneOptions](
				name: "done",
				args: [
					Arg("id", kind: FlagKind.Int),
					Arg("weight", kind: FlagKind.Float),
				],
				run: fn options: ok(
					options.id + (
						options.weight.truncate_to_int()
						or 0
					)
				)
			)
		],
	)

test "a typed positional argument fills an Int or Float field":
	tool := done_command()
	parsed := (tool.parse(["done", "7", "2.5"]) | expect_ok?)

	match parsed:
		Run(matches): (tool.run(matches) | expect_ok?) | expect_equal(9)?
		Help(_): return fail("help")

test "a positional argument that does not fit its kind names the argument":
	message := (done_command().parse(["done", "x", "1.0"]) | expect_error?).message
	message | expect_equal("cli: argument id: x is not an integer")?

test "Bool and List are not positional kinds":
	bad := Command(name: "x", args: [Arg("a", kind: FlagKind.Bool)])
	(
		(bad.parse([]) | expect_error?).message | expect_contains(
			"must be String, Int or Float"
		)?
	)
