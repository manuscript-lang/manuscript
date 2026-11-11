// conform: tags=diagnostics
// conform: phase=check
import MissingValue from "@std/errors.ms" // keep
fn first(values: List[Int]) Result[Int, MissingValue]: values.first().ok_or()
