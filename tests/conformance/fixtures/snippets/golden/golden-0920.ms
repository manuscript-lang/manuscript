// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    consume(transform: fn() Void {
        return
        )
    }
}
