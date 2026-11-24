// conform: tags=diagnostics,modules,stdlib-toml,tier-stdlib
// conform: phase=check
// conform: origin=pkg/tooling/lsp/navigation_test.go:163 TestSourceStandardLibraryNavigation
import TomlValue, parse from "@std/data/toml.ms"

fn read() Void {
	_result := parse(text: "a=1")
}
