# conform: tags=formatter,modules,parser,stdlib-toml,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/navigation_test.go:163 TestSourceStandardLibraryNavigation
import parse, TomlValue from "@std/data/toml.ms"

fn read() Unit:
    let _result = parse(text: "a=1")
