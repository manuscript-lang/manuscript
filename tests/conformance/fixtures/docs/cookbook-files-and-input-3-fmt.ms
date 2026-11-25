// conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:150
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

fn show(number Int) Result[Void, Error] {
	stdout().write(f"{number}\n")?
	return stdout().flush()
}

export fn main() Int {
	number := arguments().get_or(0, "42").parse_int()
	value := number
	if value != null {
		if show(value).is_ok() { return 0 }
	}
	return 1
}
