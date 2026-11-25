// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f(x Int) Int {
    if x > 0 {
        return 1
    }
    elif x < 0 {
        return 2
    }
    return 0
}
// expect-error: MS1000 8:5-8:9 there is no 'elif': write 'else if <condition> { ... }' for a further branch
// expect-format-exit: 1
