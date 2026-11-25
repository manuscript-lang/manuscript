// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    return 1,
}
// expect-error: MS1000 4:13-4:14 expected end of statement, found ','; commas separate items only inside (), [] or {}: put each field, case, or statement on its own line
