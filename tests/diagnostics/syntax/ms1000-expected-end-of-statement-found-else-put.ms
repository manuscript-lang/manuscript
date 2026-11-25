// conform: tags=diagnostics
// conform: phase=check
fn f(x Int) Int {
    if x > 0 { return x else: return 0 }
}
// expect-error: MS1000 4:25-4:29 expected end of statement, found 'else'; put one statement per line, and join operands with an operator or a comma inside brackets
