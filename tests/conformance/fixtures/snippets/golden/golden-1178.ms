// conform: tags=diagnostics
// conform: phase=check
fn answer() Void:
    offset := 7
    values := [1].map(outer => [2].map(inner => outer + inner + offset))
