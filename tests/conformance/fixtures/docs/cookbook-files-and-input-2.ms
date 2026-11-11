// conform: tags=control-flow,interpolation,modules,stdlib-io,tier-core,try-result
// conform: phase=run
// conform: origin=documentation/learn/common-tasks.md:120
import (
	stdin, stdout from "@std/io/io.ms",
	lines from "@std/io/streams.ms",
)

fn run() Result[Unit, Error]:
	var input = lines(stdin())

	while true:
		line := input.next()?

		if text := line:
			stdout().write("{text}\n")?
		else:
			break

	return stdout().flush()

fn main() Unit!:
	run()?
