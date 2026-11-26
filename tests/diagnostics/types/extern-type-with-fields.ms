// conform: tags=types,diagnostics,tier-core
// conform: phase=check
// An extern type is an opaque native handle: a body of fields would be accepted and then unreachable.
extern type Handle {
	size Int
}

export fn main() Int {
	return 0
}
// expect-error: MS3000 4:1 extern type Handle has no fields; the native owns its payload, so remove the body and pair it with private externs and methods
