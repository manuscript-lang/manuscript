// conform: tags=diagnostics
// conform: phase=check
fn wrap[T](callback (fn(Int) T)?) Void => return

fn apply[T, U](value T, transform fn(T) U) U => transform(value)

fn first() Void {
	offset := 7
	result := apply(
		value: 1,
		transform: outer => apply(
			value: 2,
			transform: inner => (outer + inner + offset),
		),
	)
	wrap(fn(item Int = 4) => item + offset)
}
// expect-error: MS3000 9:5 local binding result is never read; remove it, use it, or name it with a leading '_' to ignore it
