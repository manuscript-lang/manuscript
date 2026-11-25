// conform: tags=diagnostics
// conform: phase=check
fn invalid() Int {
    return [1, 2)
}
// expect-error: MS1000 4:17 mismatched closing delimiter ')'; the '[' opened at line 4:12 needs ']'
