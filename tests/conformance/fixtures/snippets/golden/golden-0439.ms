// conform: tags=diagnostics
// conform: phase=check
callback fn(value: Int) Int = apply(value: 1, transform: (base) => (item: Int = 4) => item + base)
    callback()