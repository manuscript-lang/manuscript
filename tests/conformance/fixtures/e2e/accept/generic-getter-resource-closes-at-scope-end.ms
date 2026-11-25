// conform: tags=generics,scope-cleanup,tier-core
// conform: phase=run
type Res {
	name String
}

fn move Res.close() Void! {
	print(f"close {self.name}")
	return ok(void)
}

type Cell[T] {
	v T
}

fn Cell[T].get() T {
	return self.v
}

export fn main() Int {
	a := Cell(v: Res(name: "a"))
	print(a.get().name)
	print("after a")

	b := Cell(v: Res(name: "b"))
	x := b.get()
	print(x.name)
	b.get()
	print("after b")
	return 0
}
