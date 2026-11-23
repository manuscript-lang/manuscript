// conform: tags=optional,interfaces,tier-io
// conform: phase=run
// conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

interface Shape:
	fn area() Int

type Sq:
	n: Int

fn Sq.area() Int: self.n * self.n

type Holder:
	s: Shape?

fn pick(b: Bool) Shape?:
	if b: return Sq(3)
	return null

fn take(x: Shape?) Int:
	s := x
	if s != null: return s.area()

	return -1

fn main() Void:
	h := Holder(Sq(4))
	t: Shape? := Sq(5)
	var v: Shape? = null
	v = Sq(6)
	(
		stdout()
		.write(
			f"{take(pick(true))} {take(pick(false))} {take(Sq(2))} {take(h.s)} {take(t)} {take(v)}\n"
		)
		.get()
	)
