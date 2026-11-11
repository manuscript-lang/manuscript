// conform: tags=diagnostics
// conform: phase=check
name := apply(value: 1, transform: fn(item): missing)
    name.to_string()