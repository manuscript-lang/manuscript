// conform: tags=diagnostics
// conform: phase=check
names := [1, 2].map(fn(item): missing)
    names.join(",")