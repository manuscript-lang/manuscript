// conform: tags=optional,mutation,tier-io
// conform: phase=run
import stdout from "@std/io/io.ms"

type C:
	n Int

fn var C.bump() Int:
	self.n += 1
	return self.n

fn C.get() Int: self.n

fn show(x Int?) Void:
	stdout().write(f"{(x or (-1))}\n").get()

fn closure() Void:
	var c C? = C(1)
	f := fn() Int?: c?.bump()
	show(f())
	show(f())
	show(c?.get())

fn bump_at(var xs List[C?], i Int) Int?:
	return xs[i]?.bump()

fn elements() Void:
	var xs List[C?] = [C(1), null]
	show(bump_at(xs, 0))
	show(bump_at(xs, 1))
	show(bump_at(xs, 0))

fn loop() Void:
	for i in 0..2:
		var o C? = C(i)
		v := o?.bump()
		stdout().write(f"{v}\n").get()

fn main() Void:
	closure()
	elements()
	loop()
