// conform: tags=diagnostics
// conform: phase=check
import parse, TomlValue from "@std/data/toml.ms"
fn read() Void:
    result := parse(text: "a=1")
