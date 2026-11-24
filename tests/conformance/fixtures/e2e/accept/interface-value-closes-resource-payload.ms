// conform: tags=interfaces,scope-cleanup,tier-core
// conform: phase=run
// An interface value that owns a resource closes it where it drops, through its vtable: a bound value, a returned
// one and the elements of a list, which close last to first like a list of plain resources.
type Door:
	name String

fn move Door.close() Void!:
	print(f"closed {self.name}")

interface Labeled:
	fn label() String

fn Door.label() String:
	return self.name.clone()

fn make() Labeled:
	return Door("made")

export fn main() Int:
	a Labeled := Door("bound")
	print(a.label())
	b := make()
	print(b.label())
	xs List[Labeled] := [Door("l1"), Door("l2")]
	print(xs.length())
	print("end")
	return 0
