// conform: tags=diagnostics
// conform: phase=check
fn absent[T]() T? => null

fn transform[T, U](callback fn(T) U) fn(T) U => callback

fn answer() Void {
	empty Int? := absent()
	callback fn(Int) String := transform(item => item.to_string())
}
// expect-error: MS3000 8:5 local binding empty is never read; remove it, use it, or name it with a leading '_' to ignore it
// expect-error: MS3000 9:5 local binding callback is never read; remove it, use it, or name it with a leading '_' to ignore it
