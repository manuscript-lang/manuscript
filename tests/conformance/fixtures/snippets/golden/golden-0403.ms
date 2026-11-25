// conform: tags=diagnostics
// conform: phase=check
import (
	TomlValue from "@std/data/toml.ms",
	YamlValue from "@std/data/yaml.ms",
)

fn one() Int {
	return 1
}
// expect-exit: 0
