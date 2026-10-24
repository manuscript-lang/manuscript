# conform: tags=control-flow,generics,modules,optional,stdlib-toml,tier-stdlib
# conform: phase=run
# conform: origin=internal/cli/cli_test.go:432 TestLintIgnoresBundledStandardModules
from "@std/toml.ms" import TomlValue

export def main() -> Int:
    let v: Optional[TomlValue] = none
    if v.is_some():
        return 1

    return 0
