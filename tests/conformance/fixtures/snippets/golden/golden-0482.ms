// conform: tags=diagnostics
// conform: phase=check
fn first() Unit:
    result: Result[Int, TextError] := fail("empty")