// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    (1 + 2) = 1
}
// expect-error: MS1000 4:5-4:6 assignment requires a local binding name or type field; the left side of '=' must be a name or a.field; to change a collection element, write xs[index] = value on a List or m[key] = value on a Map
