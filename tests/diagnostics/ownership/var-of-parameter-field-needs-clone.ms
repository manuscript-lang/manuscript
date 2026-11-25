// conform: tags=diagnostics,ownership,tier-core
// conform: phase=check
// `var inner = o.inner` would hand a value the caller keeps to a second owner: write the copy.
type Inner {
	tags List[String]
}

type Outer {
	inner Inner
}

fn take(var o Outer) Inner {
	var inner = o.inner
	inner.tags.append("taken")
	return inner
}

fn copy(var o Outer) Inner {
	var inner = o.inner.clone()
	inner.tags.append("taken")
	return inner
}
// expect-error: MS3000 13:19 `var inner` cannot take `o.inner`: the caller keeps it, and a `var` is a value of its own; copy it with `o.inner.clone()`, or change it in place through `o`
