// conform: tags=diagnostics
// conform: phase=check
fn sample%d(value: Int = 3) Int {
    items := [value, 2, 3]
    if value >= 0 {
        return items[0].get(0) + value
    }
    return 0
}
// expect-error: MS1000 3:10-3:11 expected '(', found '%'; a call or parameter list starts with '('
