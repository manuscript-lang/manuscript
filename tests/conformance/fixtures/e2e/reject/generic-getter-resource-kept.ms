// conform: tags=generics,diagnostics,scope-cleanup,tier-core
// conform: phase=check
type Res {
	name String
}

fn move Res.close() Void! {
	return ok(void)
}

type Cell[T] {
	v T
}

fn Cell[T].get() T {
	return self.v
}

fn keep(move r Res) Int {
	return r.name.length()
}

fn main() Int {
	cell := Cell(v: Res(name: "x"))
	return keep(cell.get())
}
