// conform: tags=diagnostics
// conform: phase=check
fn work() String:
    values := [1, 2, 3]
    text := "# A deliberately long literal with {format(value: "nested text")} that must retain its exact original spelling."
    if enabled: return text
    return text
