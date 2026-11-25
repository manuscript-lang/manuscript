// conform: tags=diagnostics,formatter,modules,stdlib-toml,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/standard_lazy_test.go:33 TestBundledSourceModulesCheckOnFirstImport
import TomlValue from "@std/data/toml.ms"

fn one() Int {
	return 1
}
// expect-exit: 0
