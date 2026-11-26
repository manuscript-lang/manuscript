// conform: tags=diagnostics,generics,closures,tier-core
// conform: phase=check
// conform: origin=type-checker bug bash
fn compose[A, B, C](f fn(A) B, g fn(B) C) fn(A) C {
	return x => g(f(x))
}

fn main() Void {
	e := compose(x => x + 1, y => f"{y}")
}
// expect-error: MS3080 9:10 cannot infer type arguments A, B, C for compose; write compose[A, B, C](...) with explicit types for A, B, C; call arguments and the expected result must determine every type parameter
// expect-error: MS3080 9:18 cannot infer callback parameter x; provide a type or a known function context: a closure bound to a variable has none, so write the parameter types and result, as in `fn(n Int) Int => n * 2`
// expect-error: MS3080 9:30 cannot infer callback parameter y; provide a type or a known function context: a closure bound to a variable has none, so write the parameter types and result, as in `fn(n Int) Int => n * 2`
