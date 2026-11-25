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

fn hold Cell[T].get() &T {
	return self.v
}

fn keep(move r Res) Int {
	return r.name.length()
}

fn main() Int {
	cell := Cell(v: Res(name: "x"))
	return keep(cell.get())
}
// expect-error: MS3000 25:22 `get` returns a reference into `cell`, which this position would keep; store `.clone()` of it, or use it in place
