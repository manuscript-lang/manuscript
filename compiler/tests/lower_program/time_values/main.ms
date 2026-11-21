import monotonic, now, nanoseconds from "@std/time.ms"

fn main() Void:
	a := monotonic()
	b := a.shift(nanoseconds(5))
	d := b.difference(a)
	c := a.compare(b)
	t := now()
	print(d.nanos + c)
	print(t.to_string())
