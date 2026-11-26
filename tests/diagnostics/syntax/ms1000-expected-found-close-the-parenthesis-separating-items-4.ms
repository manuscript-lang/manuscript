// conform: tags=diagnostics
// conform: phase=check
callback fn(value: Int) Int = apply(value: 1, transform: (base) => (item: Int = 4) => item + base)
    callback()
// expect-error: MS1000 3:18-3:19 expected ')', found ':'; close the parenthesis, separating items with commas
