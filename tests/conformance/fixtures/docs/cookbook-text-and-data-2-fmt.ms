// conform: tags=control-flow,faults,formatter,interpolation,modules,parser,records,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:204
import (
	parse, stringify from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

type Config:
	name: String
	enabled: Bool = true

fn run() Result[Unit, Error]:
	text := arguments().get(0, default: "\{\"name\":\"Sam\"\}")
	encoded := parse[Config](text)?
		| stringify?
	stdout().write("{encoded}\n")?
	return stdout().flush()

fn main() Unit!:
	run()?
