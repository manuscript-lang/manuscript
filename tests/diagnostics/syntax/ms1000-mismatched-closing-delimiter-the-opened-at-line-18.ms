// conform: tags=diagnostics
// conform: phase=check
// Add two numbers.
fn sum(left Int, right Int) Int {
    return left + right
}
fn answer() Int {
    return sum(left: 1, ri|
}
// expect-error: MS1000 9:1 mismatched closing delimiter '}'; the '(' opened at line 8:15 needs ')'
