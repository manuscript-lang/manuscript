// conform: tags=diagnostics,formatter,modules,stdlib-toml,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/navigation_test.go:163 TestSourceStandardLibraryNavigation
import TomlValue, parse from "@std/data/toml.ms"

fn read() Void {
	_result := parse(text: "a=1")
}
// expect-exit: 0
