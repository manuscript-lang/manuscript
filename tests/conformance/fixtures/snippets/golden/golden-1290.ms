// conform: tags=diagnostics
// conform: phase=check
fn first(values: List[Int]) Result[Int, MissingValue]: values.first().ok_or()
