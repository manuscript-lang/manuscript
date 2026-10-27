# conform: tags=diagnostics,modules,stdlib-toml,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/navigation_test.go:163 TestSourceStandardLibraryNavigation
from "@std/toml.ms" import parse, TomlValue

def read() -> Unit:
    let _result = parse(text: "a=1")
