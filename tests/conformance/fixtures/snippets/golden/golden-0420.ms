// conform: tags=diagnostics
// conform: phase=check
import StringBuilder from "@std/string.ms"
fn fragment() String: return "x"
fn probe(flag: Bool) String:
    b := StringBuilder()
    