import (
	Bytes from "@std/bytes.ms",
	CommandOutput, RunOptions, SpawnOptions, Subprocess from "@std/os/process.ms",
)

export type Quiet:
	code: Int

fn Quiet.run(
	program: String,
	arguments: List[String],
	options: RunOptions = RunOptions(),
) CommandOutput!:
	return ok(CommandOutput(self.code, options.input.clone(), "".to_bytes(), 0))

fn Quiet.spawn(
	program: String,
	arguments: List[String],
	options: SpawnOptions,
) Subprocess!:
	return error(Error("process: service unavailable", kind: "EAGAIN"))
