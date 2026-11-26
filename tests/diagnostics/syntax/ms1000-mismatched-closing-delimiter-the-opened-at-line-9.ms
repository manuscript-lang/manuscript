// conform: tags=diagnostics
// conform: phase=check
fn main() Void {
    if true { let ( }
        a = 1
    )
}
// expect-error: MS1000 4:21 mismatched closing delimiter '}'; the '(' opened at line 4:19 needs ')'
