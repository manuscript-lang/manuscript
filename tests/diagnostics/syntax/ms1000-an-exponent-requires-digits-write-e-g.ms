// conform: tags=diagnostics
// conform: phase=check
fn value() Float {
    return 1e+
}
// expect-error: MS1000 4:15 an exponent requires digits; write e.g. 1e3 or 2.5e-4
