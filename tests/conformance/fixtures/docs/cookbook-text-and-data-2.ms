// conform: tags=control-flow,diagnostics,faults,interpolation,modules,records,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
// conform: phase=check
// conform: origin=documentation/learn/common-tasks.md:204
import (
	parse, stringify from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

type Config {
	name String
	enabled Bool = true
}

fn run() Result[Void, Error] {
	text := arguments().get_or(0, "{\"name\":\"Sam\"}")
	encoded := parse[Config](text)?
		| stringify?
	stdout().write(f"{encoded}\n")?
	return stdout().flush()
}

fn main() Void! {
	run()?
}
// expect-exit: 0
