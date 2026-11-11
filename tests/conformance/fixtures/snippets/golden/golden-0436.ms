// conform: tags=diagnostics
// conform: phase=check
offset := 7
    values := [1, 2].map(fn(outer): [3, 4].map(fn(inner): outer + inner + offset))