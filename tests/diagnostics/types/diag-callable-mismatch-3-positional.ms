// conform: tags=diagnostics,closures,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn source(_0 Int) String => "text"

fn exercise() Void {
	callback fn(Int) Int := source
}
// expect-error: MS3001 7:29 expected fn(Int) Int, found fn(Int) String (in the initializer of 'callback')
