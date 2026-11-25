// conform: tags=diagnostics
// conform: phase=check
fn probe(flag Bool) Int {
    values List[Int] := []
    var i = 0
    while i < 100 {
    }
}
// expect-error: MS1000 7:5-7:6 a block cannot be empty; add at least one statement, or write '...' inside the braces for a runtime-bound declaration
