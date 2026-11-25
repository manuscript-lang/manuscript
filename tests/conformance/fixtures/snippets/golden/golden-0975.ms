// conform: tags=diagnostics
// conform: phase=check
fn unfinished(
fn valid() Int {
    return 1
}
// expect-error: MS1000 8:1 unterminated delimiter '(' opened at line 3:14; add the matching ')' before the end of the file
