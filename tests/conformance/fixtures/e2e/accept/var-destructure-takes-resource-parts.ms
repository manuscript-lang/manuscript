// conform: tags=destructuring,scope-cleanup,tier-core
// conform: phase=run
// A `var` pattern takes the resource parts of a record it is given: reassigning a part closes the old one, and
// every part closes once, where its name goes out of scope.
type Handle:
	id Int

fn move Handle.close() Void!:
	print(f"closed {self.id}")
	return ok()

type Pair:
	first Handle
	second Handle

fn make() Pair:
	return Pair(first: Handle(id: 1), second: Handle(id: 2))

fn main() Void!:
	pair := make()
	var {first, second} = pair
	first = Handle(id: 3)
	print(second.id + first.id)
	return ok()
