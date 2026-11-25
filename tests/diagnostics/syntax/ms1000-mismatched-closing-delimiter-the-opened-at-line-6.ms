// conform: tags=diagnostics
// conform: phase=check
fn value() Void {
    other(value: [1)
}
// expect-error: MS1000 4:20 mismatched closing delimiter ')'; the '[' opened at line 4:18 needs ']'
