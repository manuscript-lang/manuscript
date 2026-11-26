// conform: tags=diagnostics
// conform: phase=check
// A name cannot keep a view of a part of a temporary whose own `close` runs when the
// statement ends.
type Marker {
	id Int
}

fn move Marker.close() Void! { return ok() }

type Holder {
	marker Marker
}

fn move Holder.close() Void! { return ok() }

fn hold Holder.inner() &Marker => self.marker

fn run() Void {
	m := Holder(Marker(1)).inner()
	void m.id
}
// expect-error: MS3000 20:28 `Holder(..).inner(..)` borrows a part of a temporary that closes when this statement ends; bind the owner first and borrow from it
