// conform: tags=optional,tier-core
// conform: phase=check
// conform: origin=nullable-types stage 3
export fn main() Void:
	a Int? := 3
	b Int? := null
	print(f"{a == null} {b != null} {null == a}")
	c := a or 5
	d Int? := b or a
	e := b or null
	print(f"{c} {d} {e}")
	g := a or "x"
	h := 1 or 2
	print(f"{g} {h}")
