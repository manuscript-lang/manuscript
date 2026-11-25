// conform: tags=diagnostics
// conform: phase=check
import TomlValue from "@std/data/toml.ms"

export fn main() Int {
	v TomlValue? := null
	if v != null { return 1 }

	return 0
}
