// conform: tags=diagnostics
// conform: phase=check
fn value() String {
    return "a	b"
}
// expect-error: MS1001 4:15 literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}
