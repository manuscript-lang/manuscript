// conform: tags=control-flow,formatter,generics,modules,optional,parser,stdlib-toml,tier-stdlib
// conform: phase=parse
// conform: origin=internal/cli/cli_test.go:432 TestLintIgnoresBundledStandardModules
import TomlValue from "@std/data/toml.ms"

export fn main() Int {
	v TomlValue? := null
	if v != null { return 1 }

	return 0
}
