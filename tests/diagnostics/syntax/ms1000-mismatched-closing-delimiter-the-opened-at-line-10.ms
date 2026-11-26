// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    return (1
}
// expect-error: MS1000 5:1 mismatched closing delimiter '}'; the '(' opened at line 4:12 needs ')'
