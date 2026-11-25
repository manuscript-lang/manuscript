// conform: tags=diagnostics,tier-core
// conform: phase=check
fn width(text String) Int! {
	return ok(text.length())
}

fn total(items List[String]) Int! {
	widths := items.map(item => width(item)?)
	return ok(widths.length())
}
// expect-error: MS3000 8:33 '?' inside a lambda returns from the lambda, whose result is Int; write the lambda's result as a Result, as in `fn(x T) Result[U, E] => ...`, or handle the failure with 'if value := x', 'match' or a loop
