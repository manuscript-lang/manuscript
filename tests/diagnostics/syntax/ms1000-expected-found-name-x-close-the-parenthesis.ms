// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    n := [1].map(x x + 1)
    return 0
}
// expect-error: MS1000 4:20-4:21 expected ')', found name 'x'; close the parenthesis, separating items with commas
