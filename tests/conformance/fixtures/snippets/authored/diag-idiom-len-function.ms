// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	a := len([1])
}
// expect-error: MS2001 5:10 unknown binding len; there is no len() function: call the length member, e.g. xs.length() (String length is bytes; scalar_length counts scalars)
