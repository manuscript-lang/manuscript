package msruntime

// unitRun adapts a body that returns Unit to a test body that succeeds when it completes.
func unitRun(body func(*Execution) Unit) func(*Execution) Result[Unit, Error] {
	return func(ctx *Execution) Result[Unit, Error] {
		body(ctx)
		return Ok[Unit, Error](Unit{})
	}
}
