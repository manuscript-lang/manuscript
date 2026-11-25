// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := [1].first().unwrap_or(0)
}
// expect-error: MS2001 5:22 unknown or ambiguous member unwrap_or on Int?; read an Optional with x.get_or(default), x.get_or_else(create) for a lazy fallback, or `if x != null { ... }` to test it; x.get() with no default faults on null
