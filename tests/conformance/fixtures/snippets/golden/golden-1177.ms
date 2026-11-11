// conform: tags=diagnostics
// conform: phase=check
fn answer() Unit:
    values := [1, 2].map(fn value: value + 1)
