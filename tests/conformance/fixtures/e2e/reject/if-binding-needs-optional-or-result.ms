// conform: tags=control-flow,tier-core
// conform: phase=check
// `if name := value:` binds the payload of an Optional or Result; a List `get` answers the element itself.
fn main() Void {
	items := [1, 2]
	if item := items[0] {
		print(item)
	}
}
