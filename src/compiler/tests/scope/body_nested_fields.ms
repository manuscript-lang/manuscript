type Inner:
	x: Int

type Outer:
	inner: Inner
	y: Int

fn read(o: Outer) Int:
	return o.inner.x + o.y

fn build() Int:
	o := Outer(Inner(3), 4)
	return o.inner.x
