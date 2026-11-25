// conform: tags=diagnostics
// conform: phase=check
fn f(a Int, b Int) Bool {
    return a > 0
        and b > 0
}
// expect-error: MS1000 5:9-5:12 expected an expression, found 'and'; write a value, name, call, or literal here
