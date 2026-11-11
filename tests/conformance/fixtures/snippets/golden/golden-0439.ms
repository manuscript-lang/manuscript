// conform: tags=diagnostics
// conform: phase=check
callback: fn(value: Int) Int = apply(value: 1, transform: fn(base): fn(item: Int = 4): item + base)
    callback()