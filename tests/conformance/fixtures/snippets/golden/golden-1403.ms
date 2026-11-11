// conform: tags=diagnostics
// conform: phase=check
import StringBuilder from "@std/string.ms"
fn probe() String:
    b := StringBuilder()
    var i = 0
    while i < 321:
        b.append("x")
        i += 1
    return b.freeze()
