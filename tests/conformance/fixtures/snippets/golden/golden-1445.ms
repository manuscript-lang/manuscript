// conform: tags=diagnostics
// conform: phase=check
fn sum(value: Int) Int:
    return value + 1
test "fault":
    impossible := sum(value: 9223372036854775807)
