// conform: tags=diagnostics
// conform: phase=check
fn f() String {
    return "a\q"
}
// expect-error: MS1001 4:14 unknown text escape \\q; valid escapes are \\n \\t \\r \\\\ \\" and \\u{H}
