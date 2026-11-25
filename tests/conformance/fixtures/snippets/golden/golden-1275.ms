// conform: tags=diagnostics
// conform: phase=check
import TomlValue, parse from "@std/data/toml.ms"

fn read() Void {
	result := parse(text: "a=1")
}
// expect-error: MS3000 6:5 local binding result is never read; remove it, use it, or name it with a leading '_' to ignore it
