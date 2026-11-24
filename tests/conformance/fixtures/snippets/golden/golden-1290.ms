// conform: tags=diagnostics
// conform: phase=check
fn first(values: List[Int]) Result[Int, MissingValue]: ok_or(
	values.first(),
	Error("missing"),
)
