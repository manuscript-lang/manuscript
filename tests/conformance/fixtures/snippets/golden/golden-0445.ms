// conform: tags=diagnostics
// conform: phase=check
callback fn(left: Int, right: Int) Int = fn(a, b) => a - b
    callback(a: 1, b: 2)
// expect-error: MS1000 3:17-3:18 expected ')', found ':'; close the parenthesis, separating items with commas
