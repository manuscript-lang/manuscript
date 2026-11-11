// conform: tags=diagnostics
// conform: phase=check
fn label(value: Int) String:
    return "{value}"
test "methods":
    labels := [1].map(transform: label)
    convert := [2].map[String]
    text := " hello ".trim()
