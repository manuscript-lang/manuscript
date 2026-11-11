// conform: tags=diagnostics
// conform: phase=check
fn first() Unit:
    value: fn(String) Result[Int, TextError] := fail