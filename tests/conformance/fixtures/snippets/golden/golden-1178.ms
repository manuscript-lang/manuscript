// conform: tags=diagnostics
// conform: phase=check
fn answer() Void:
    offset := 7
    values := [1].map(fn outer: [2].map(fn inner: outer + inner + offset))
