// conform: tags=diagnostics
// conform: phase=check
enum Optional[T]:
	T
	null

fn wrong(value Int?) Result[Int, String]: ok_or(value, "missing")
