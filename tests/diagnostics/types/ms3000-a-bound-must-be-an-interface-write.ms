// conform: tags=diagnostics
// conform: phase=check
type Data {
	value Int
}

fn record[T Data](value T) Void => return
// expect-error: MS3000 7:13 a bound must be an interface; write [T SomeInterface], where SomeInterface is declared with 'interface'
