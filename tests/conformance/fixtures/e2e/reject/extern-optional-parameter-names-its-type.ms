// conform: tags=types,diagnostics,tier-core
// conform: phase=check
// An Optional parameter has an implicit default, but what an extern rejects is its type: the message names that
// rather than a default the author never wrote.
extern fn maybe(value Int?) Int

export fn main() Int {
	return 0
}
