// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    return [1][0:2]
}
// expect-error: MS1000 4:17-4:18 there is no slice syntax; call slice(start: 0, end: 2) on a List or String
