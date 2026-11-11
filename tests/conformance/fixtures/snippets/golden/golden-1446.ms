// conform: tags=diagnostics
// conform: phase=check
fn divide(value: Int, divisor: Int) Int:
    return value / divisor
test "fault":
    impossible := divide(value: 3, divisor: 0)
