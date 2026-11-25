// conform: tags=diagnostics
// conform: phase=check
fn absent[T]() T? => null

fn transform[T, U](hold callback fn(T) U) &fn(T) U => callback

fn answer() Void {
	empty Int? := absent()
	callback fn(Int) String := transform(item => item.to_string())
}
