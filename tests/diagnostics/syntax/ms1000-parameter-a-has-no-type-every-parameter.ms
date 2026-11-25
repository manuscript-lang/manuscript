// conform: tags=diagnostics
// conform: phase=check
fn broken(a ) Int {
    return 1
}
fn ok() Int {
    return 2
}
// expect-error: MS1000 3:11-3:12 parameter 'a' has no type; every parameter is written name Type, e.g. a Int
