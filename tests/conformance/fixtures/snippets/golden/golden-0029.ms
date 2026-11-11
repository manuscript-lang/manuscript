// conform: tags=diagnostics
// conform: phase=check
import TomlValue from "@std/data/toml.ms"

export fn main() Int:
    v: TomlValue? := none
    if v.is_some():
        return 1
    return 0
