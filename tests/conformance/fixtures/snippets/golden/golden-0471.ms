// conform: tags=diagnostics
// conform: phase=check
fn first(values: List[Int]) Result[Int, MissingValue]: ok_or(
	values.first(),
	Error("missing"),
)

fn message(values: List[Int]) String: first(values).err().message()

fn widen(cause: MissingValue) Error: cause
