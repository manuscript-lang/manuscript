// conform: tags=diagnostics
// conform: phase=check
import parse from "@std/data/json.ms"
type Item:
    parse: Int
fn answer() Item:
    return Item(parse: 1)
