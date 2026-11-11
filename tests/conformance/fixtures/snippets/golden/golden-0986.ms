// conform: tags=diagnostics
// conform: phase=check
// café 🦀
fn use(value: Envelope) Int:
    match value:
        Pair(
            _,
            NotFound,
        ): return 1
