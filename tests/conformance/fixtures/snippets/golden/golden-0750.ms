// conform: tags=diagnostics
// conform: phase=check
fn probe() Int {
    var sum = 9223372036854775807
    var peer = 0
    var i = 0
    while i < 1000 {
    }
}
// expect-error: MS1000 8:5-8:6 a block cannot be empty; add at least one statement, or write '...' inside the braces for a runtime-bound declaration
