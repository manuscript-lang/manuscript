// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f(g Callable[[Int], Int]) Int {
    return 0
}
// expect-error: MS1000 4:16-4:17 there is no Callable[...] type; a function type is written fn(Int) Int: parameter types in parentheses, then the result type
// expect-format-exit: 1
