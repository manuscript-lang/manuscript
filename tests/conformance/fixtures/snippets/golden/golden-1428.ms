// conform: tags=diagnostics
// conform: phase=check
fn crash(%s) %s {
    return %s
}
fn main() Void {
    values := %s
    result := values.%s(%s)
}
