// conform: tags=diagnostics,formatter,modules,stdlib-toml,stdlib-yaml,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/standard_lazy_test.go:46 TestBundledSourceModulesCheckOnceConcurrently
import (
	TomlValue from "@std/data/toml.ms",
	YamlValue from "@std/data/yaml.ms",
)

fn one() Int {
	return 1
}
// expect-exit: 0
