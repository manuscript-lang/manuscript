// conform: tags=diagnostics,generics,try-result,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
interface Named {
	fn name() String
}

fn describe[E Named](item E) String => item.name()

fn main() Void {
	_message := describe("missing")
}
// expect-error: MS3000 11:17 String does not satisfy Named; pass a type that already implements it
