// conform: tags=diagnostics
// conform: phase=check
callback fn(value: Int) Int = fn(item: Int = 4) => item
    callback()
// expect-error: MS1000 3:18-3:19 expected ')', found ':'; close the parenthesis, separating items with commas
