// conform: tags=diagnostics,closures,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn source(_0 Int) Int => _0

fn exercise() Void {
	callback fn(String) Int := source
}
// expect-error: MS3001 7:32 expected fn(String) Int, found fn(Int) Int (in the initializer of 'callback')
