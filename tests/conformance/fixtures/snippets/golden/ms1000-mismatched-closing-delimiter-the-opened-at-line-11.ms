// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    consume(transform: fn() Void {
        return
        )
    }
}
// expect-error: MS1000 6:9 mismatched closing delimiter ')'; the '{' opened at line 4:34 needs '}'
