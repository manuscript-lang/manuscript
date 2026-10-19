# conform: tags=aliasing,control-flow,generics,modules,optional,stdlib-toml,tier-stdlib
# conform: phase=run
# conform: origin=internal/cli/cli_test.go:432 TestLintIgnoresBundledStandardModules
import TomlValue from "@std/toml.ms"

export fn main() Int:
    let v: Optional[TomlValue] = none
    if v.is_some():
        return 1
    return 0
