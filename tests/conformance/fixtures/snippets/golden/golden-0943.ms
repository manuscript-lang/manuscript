// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    if true { use() else if false: use() }
}
