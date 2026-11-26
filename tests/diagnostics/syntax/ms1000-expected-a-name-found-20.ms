// conform: tags=diagnostics
// conform: phase=check
fn crash(%s) %s {
    return %s
}
fn main() Void {
    values := %s
    result := values.%s(%s)
}
// expect-error: MS1000 3:10-3:11 expected a name, found '%'
// expect-error: MS1000 7:15-7:16 expected an expression, found '%'; write a value, name, call, or literal here
// expect-error: MS1000 8:22-8:23 expected a name, found '%'
