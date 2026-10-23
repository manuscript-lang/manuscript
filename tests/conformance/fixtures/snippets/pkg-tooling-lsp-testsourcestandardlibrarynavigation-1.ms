# conform: tags=diagnostics,modules,stdlib-toml,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/navigation_test.go:163 TestSourceStandardLibraryNavigation
import {parse, TomlValue} from "@std/toml.ms"

fn read() Unit:
    let result = parse(text: "a=1")
