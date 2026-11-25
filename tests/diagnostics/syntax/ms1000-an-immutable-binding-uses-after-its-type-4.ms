// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    const x = 1
    return x
}
// expect-error: MS1000 4:13-4:14 an immutable binding uses ':=' after its type: write 'x Type := value'; '=' binds only after 'var'
// expect-fix: 4:13-4:14 ":="
