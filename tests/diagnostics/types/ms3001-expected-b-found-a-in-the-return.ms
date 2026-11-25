// conform: tags=diagnostics
// conform: phase=check
interface A {
	fn a() Int
}

interface B {
	fn b() Int
}

fn f(value A) B => value
// expect-error: MS3001 11:20 expected B, found A (in the return value); use a concrete value implementing B
