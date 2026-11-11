import (
	Bytes from "@std/bytes.ms",
	CommandOutput,
	Commands,
	RunOptions,
	SpawnOptions,
	Subprocess from "@std/os/process.ms",
)

// Shifts the node ids below so that `Echo.run` has the id of a method in another module
// (`second.ms` or the standard library): defaults must be found by module and id.
export fn padding() Int:
	var total = 0
	total += 0
	total += 1
	total += 2
	total += 3
	total += 4
	return total

export type Echo:
	code: Int

impl Commands for Echo:
	fn run(program: String, arguments: List[String], options: RunOptions) CommandOutput!:
		return ok(CommandOutput(self.code, options.input.clone(), "".to_bytes(), 0))

	fn spawn(
		program: String,
		arguments: List[String],
		options: SpawnOptions,
	) Subprocess!:
		return error(Error("process: service unavailable", kind: "EAGAIN"))
