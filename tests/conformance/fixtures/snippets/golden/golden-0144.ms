// conform: tags=diagnostics
// conform: phase=check
import hex_decode from "@std/data/encoding.ms"
fn wrong() Result[Unit, JsonError]:
    bytes := hex_decode(text: "ff", max_bytes: 1)?
    return ok(value: unit)
