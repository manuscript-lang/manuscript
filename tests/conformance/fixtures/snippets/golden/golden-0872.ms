// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    return 1;
}
// expect-error: MS1000 4:13-4:14 unexpected source character ';'; Manuscript ends a statement at the end of the line, so remove the semicolon
// expect-fix: 4:13-4:14 ""
