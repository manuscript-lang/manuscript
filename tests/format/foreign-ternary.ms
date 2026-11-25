// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f(x Int) Int {
    return 1 if x > 0 else 2
}
// expect-error: MS1000 5:14-5:16 expected end of statement, found 'if'; there is no inline conditional expression 'a if c else b': write 'if c { a } else { b }', or use an if statement
// expect-format-exit: 1
