// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// A statement that binds a name closes the resources of its temporaries where it ends,
// whether it reads a resource field in place or an element of a returned list.
type Door {
	name String
}

fn move Door.close() Void! {
	print(f"closed {self.name}")
}

fn Door.label() String {
	return self.name.clone()
}

type Pair {
	a Door
	b Door
}

fn pair() Pair {
	return Pair(Door("pa"), Door("pb"))
}

fn doors() List[Door] {
	return [Door("l1"), Door("l2")]
}

export fn main() Int {
	first := pair().a.label()
	print("--field")

	second := doors()[1].label()
	print("--index")
	print(f"{first} {second}")
	return 0
}
// expect-exit: 0
// expect-stdout: closed pb
// expect-stdout: closed pa
// expect-stdout: --field
// expect-stdout: closed l2
// expect-stdout: closed l1
// expect-stdout: --index
// expect-stdout: pa l2
