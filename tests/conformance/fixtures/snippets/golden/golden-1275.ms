// conform: tags=diagnostics
// conform: phase=check
import TomlValue, parse from "@std/data/toml.ms"

fn read() Void {
	result := parse(text: "a=1")
}
