// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    finally
}
// expect-error: MS1000 5:5-5:12 'finally' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a Result with 'call()?', or handle it with 'if value := result { ... }' and an else branch
// expect-format-exit: 1
