// conform: tags=control-flow,tier-core
// conform: phase=check
// `if name := value:` binds the payload of an Optional or Result; a List `get` answers the element itself.
fn main() Void {
	items := [1, 2]
	if item := items[0] {
		print(item)
	}
}
// expect-error: MS3000 6:16 an if binding requires an Optional or Result, found Int; use 'if' for a Bool condition or 'match' for other alternatives
