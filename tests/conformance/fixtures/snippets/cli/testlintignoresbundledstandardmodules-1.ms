# conform: tags=control-flow,generics,modules,optional,stdlib-toml,tier-stdlib
# conform: phase=run
# conform: origin=internal/cli/cli_test.go:432 TestLintIgnoresBundledStandardModules
import TomlValue from "@std/data/toml.ms"

export fn main() Int:
    let v: TomlValue? = none
    if v.is_some():
        return 1

    return 0
