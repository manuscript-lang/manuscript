// conform: tags=diagnostics
// conform: phase=check
s := "a\qb"
// expect-error: MS1001 3:8 unknown text escape \\q; valid escapes are \\n \\t \\r \\\\ \\" and \\u{H}
