// conform: tags=diagnostics,control-flow,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int {
	x := 1
	f := x => return x + 1
	return f(x)
}
// expect-error: MS3080 6:10 cannot infer callback parameter x; provide a type or a known function context: a closure bound to a variable has none, so write the parameter types and result, as in `fn(n Int) Int => n * 2`
// expect-error: MS3000 6:10 binding x shadows an outer binding of the same name; rename one of them, or assign to the outer 'var'
