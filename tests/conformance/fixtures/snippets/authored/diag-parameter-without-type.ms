// conform: tags=diagnostics,tier-core
// conform: phase=check
fn add(a, b) Int {
    return a + b
}

export fn main() Int {
    return 0
}
// expect-error: MS1000 3:8-3:9 parameter 'a' has no type; every parameter is written name Type, e.g. a Int
