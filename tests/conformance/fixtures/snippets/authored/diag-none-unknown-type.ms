// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	y Option[Int] := null
}
// expect-error: MS2001 5:7 unknown type Option; an optional type is written T?, e.g. Int? or (fn(Int) Int)?
