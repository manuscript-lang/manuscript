// conform: tags=diagnostics
// conform: phase=check
// A resource field leaves a local `var` holder only as `part := holder.field`, refilled
// by the next statement.
type Marker {
	id Int
}

fn move Marker.close() Void! { return ok() }

type Holder {
	marker Marker
}

fn run() Void {
	var holder = Holder(Marker(1))
	var taken = holder.marker
	void taken.id
}
// expect-error: MS3000 17:24 `var taken` cannot take the resource `holder.marker`: it would leave `holder` with a hole; use it in place, or take it with `part := holder.marker` and refill `holder.marker = ...` in the next statement
