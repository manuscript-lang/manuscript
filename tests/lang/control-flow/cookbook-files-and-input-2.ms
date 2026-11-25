// conform: tags=control-flow,formatter,interpolation,modules,stdlib-io,tier-core,try-result
// conform: phase=run,parse
// conform: origin=documentation/learn/common-tasks.md:120
import (
	stdin, stdout from "@std/io/io.ms",
	lines from "@std/io/steps.ms",
)

fn run() Result[Void, Error] {
	var input = lines(stdin())

	while true {
		line := input.next()?
		text := line

		if text != null {
			stdout().write(f"{text}\n")?
		} else {
			break
		}
	}

	return stdout().flush()
}

fn main() Void! {
	run()?
}
// expect-exit: 0
