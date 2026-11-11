// conform: tags=diagnostics
// conform: phase=check
import parse, TomlValue from "@std/data/toml.ms"
fn read() Unit:
    result := parse(text: "a=1")
