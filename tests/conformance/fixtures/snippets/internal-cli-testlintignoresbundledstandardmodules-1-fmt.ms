# conform: tags=control-flow,formatter,generics,modules,optional,parser,stdlib-toml,tier-stdlib
# conform: phase=parse
# conform: origin=internal/cli/cli_test.go:432 TestLintIgnoresBundledStandardModules
from "@std/toml.ms" import TomlValue

export def main() -> Int:
    let v: Optional[TomlValue] = none
    if v.is_some():
        return 1

    return 0
