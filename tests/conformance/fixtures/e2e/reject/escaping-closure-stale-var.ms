// conform: tags=closures,mutation,diagnostics,tier-core
// conform: phase=check
fn make() fn(Int) Int:
    var offset = 1
    factory := fn() fn(Int) Int:
        return fn inner:
            return inner + offset
    nested := factory()
    offset = 100
    return nested
