// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    if true {
    }
}
// expect-error: MS1000 5:5-5:6 a block cannot be empty; add at least one statement, or write '...' inside the braces for a runtime-bound declaration
