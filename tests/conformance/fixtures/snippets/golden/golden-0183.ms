// conform: tags=diagnostics
// conform: phase=check
type Callback {
	value fn(Int) Int
}

fn example() Void {
	callback := Callback(value => value + 1)
}
// expect-error: MS3000 8:5 local binding callback is never read; remove it, use it, or name it with a leading '_' to ignore it
