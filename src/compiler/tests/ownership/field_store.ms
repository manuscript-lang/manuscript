type Inner:
	x: Int

type Outer:
	inner: Inner
	y: Int

fn bump() Int:
	var o = Outer(Inner(1), 2)
	o.y = 5
	o.inner.x = o.y + 1
	return o.inner.x

fn immutable() Int:
	o := Outer(Inner(1), 2)
	o.y = 5
	return o.y

fn param(var o: Outer) Int:
	o.y = 9
	return o.y

fn compound() Int:
	var o = Outer(Inner(1), 2)
	o.y += 3
	return o.y

fn written_only() Int:
	var o = Outer(Inner(1), 2)
	o.y = 4
	return 0

type Named:
	name: String
	n: Int

fn replace_text() Int:
	var v = Named("a", 1)
	v.name = "b"
	return v.n

fn replace_record() Int:
	var o = Outer(Inner(1), 2)
	o.inner = Inner(7)
	return o.inner.x

fn move_in(var o: Outer, inner: Inner) Int:
	o.inner = inner
	return o.y

fn param_not_var(o: Outer) Int:
	o.y = 1
	return o.y

fn borrowed_disjoint() Int:
	var o = Outer(Inner(1), 2)
	r := o.inner
	o.y = 3
	return r.x

fn borrowed_overlap() Int:
	var o = Outer(Inner(1), 2)
	r := o.inner
	o.inner = Inner(4)
	return r.x
