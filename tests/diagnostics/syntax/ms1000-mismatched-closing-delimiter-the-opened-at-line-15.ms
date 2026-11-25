// conform: tags=diagnostics
// conform: phase=check
fn sum(left Int, right Int) Int {
    return left + right
}
fn answer(input: Int) Int {
    return sum(left: inp|
}
// expect-error: MS1000 8:1 mismatched closing delimiter '}'; the '(' opened at line 7:15 needs ')'
