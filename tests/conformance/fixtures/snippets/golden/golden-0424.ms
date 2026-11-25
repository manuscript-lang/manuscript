// conform: tags=diagnostics
// conform: phase=check
fn probe() Int {
    values: List[Int] = [
}
// expect-error: MS1000 5:1 mismatched closing delimiter '}'; the '[' opened at line 4:25 needs ']'
