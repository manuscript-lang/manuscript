// conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:177
import (
	parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

fn run() Result[Void, Error] {
	text := parse[String](arguments().get_or(0, "\"hello\""))?
	stdout().write(f"{text}\n")?
	return stdout().flush()
}

fn main() Void! {
	run()?
}
