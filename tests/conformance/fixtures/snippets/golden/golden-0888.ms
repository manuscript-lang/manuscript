// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    throw "x"
    return 0
}
// expect-error: MS1000 4:5-4:10 'throw' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a Result with 'call()?', or handle it with 'if value := result { ... }' and an else branch
