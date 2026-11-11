// conform: tags=diagnostics
// conform: phase=check
fn first(values: List[Int]) Result[Int, MissingValue]: values.first().ok_or()
fn message(values: List[Int]) String: first(values).err().message()
fn widen(cause: MissingValue) Error: cause
