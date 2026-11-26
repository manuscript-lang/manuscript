// conform: tags=testing,tier-core
// conform: phase=check
fn absent() Int? {
	return Optional[Int].null
}
// expect-error: MS2001 4:26 Optional has no qualified cases; write null or the plain value where a T? is expected, and put the type on the binding, e.g. x Int? := null
