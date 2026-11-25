// conform: tags=diagnostics
// conform: phase=check
fn call[T](operation fn() T) T {
	return operation()
}

fn get() Result[Int, Error] => return ok(value: 1)

fn note() Void => return

fn run() Void {
	call(
		operation: fn() Int {
			match get() {
				ok(n) => note()
				error(e) => note()

			} return 0
		}
	)
}
// expect-error: MS3000 15:20 local binding n is never read; remove it, use it, or name it with a leading '_' to ignore it
// expect-error: MS3000 16:23 local binding e is never read; remove it, use it, or name it with a leading '_' to ignore it
