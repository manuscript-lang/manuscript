// conform: tags=ownership,tier-core
// conform: phase=check
// A record built from a part of a borrowed value would copy it behind the source's
// back: `.clone()` is the only copy.
type Box {
	items List[Int]
}

type Holder {
	rows List[List[Int]]
}

fn Holder.first() Box {
	return Box(self.rows[0])
}

fn main() Void {
	h := Holder([[1, 2]])
	print(h.first().items.length())
}
// expect-error: MS3000 14:21 `self.rows[0]` belongs to `self`, so a new owner would get a hidden copy; write `self.rows[0].clone()` to copy it
