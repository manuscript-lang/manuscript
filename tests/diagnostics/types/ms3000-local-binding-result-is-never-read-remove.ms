// conform: tags=diagnostics
// conform: phase=check
fn run[T](operation fn() T) T {
	return operation()
}

interface Read {
	fn get() Int
}

fn call(view Read) Void {
	callback := fn(value Int = view.get()) Int {
		return value
	}
	task := fn() Int {
		return callback()
	}
	result := run(task)
}
// expect-error: MS3000 18:5 local binding result is never read; remove it, use it, or name it with a leading '_' to ignore it
