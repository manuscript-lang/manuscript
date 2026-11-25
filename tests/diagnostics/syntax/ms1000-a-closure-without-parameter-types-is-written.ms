// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    n := [1].map(fn(x) => x + 1)
    return 0
}
// expect-error: MS1000 4:24-4:26 a closure without parameter types is written without 'fn': x => x + 1, (a, b) => a + b or () => 1
