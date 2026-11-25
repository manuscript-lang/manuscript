// conform: tags=diagnostics
// conform: phase=check
fn value() String {
    return "\u{d800}"
}
// expect-error: MS1001 4:20 invalid Unicode scalar escape; use 1 to 6 hexadecimal digits for a value up to 10FFFF that is not a surrogate (D800-DFFF)
