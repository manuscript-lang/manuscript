// conform: tags=diagnostics,tier-core
// conform: phase=check
fn apply(f fn(Int) Int, x Int) Int {
	return f(x)
}

export fn main() Int {
	print(apply((a, b) => a + b, 1))
	return 0
}
// expect-error: MS3000 8:17 callback parameter count does not match its context; the context expects 1 parameter, found 2, so write exactly the parameters its context declares
