# conform: tags=formatter,modules,parser,stdlib-toml,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/navigation_test.go:163 TestSourceStandardLibraryNavigation
from "@std/toml.ms" import parse, TomlValue

def read() -> Unit:
    let _result = parse(text: "a=1")
