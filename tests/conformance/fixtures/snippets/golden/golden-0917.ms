// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    return values[0, 1]
}
// expect-error: MS1000 4:20-4:21 expected ']', found ','; close the bracket, separating items with commas
