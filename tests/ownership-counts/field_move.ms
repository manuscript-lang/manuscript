// expect-debug: allocs=17 alloc_bytes=182
// expect-release: allocs=13 alloc_bytes=126
// expect-stdout: 6
// expect-stdout: 3
// expect-stdout: 2
// `items_of` lends a field of its parameter; over a temporary (`items_of(Big(..))`) the caller owns a
// copy of that field in Debug (one 24-byte list), and copyelim moves it out of the
// dying record in Release (type.release). A field of an owned record moves out at its
// last use; the rest of the record is still cleaned up exactly once.
import stdout from "@std/io/io.ms"

type Big:
	name: String
	items: List[Int]

type Wrap:
	inner: Big
	tag: Int

fn items_of(b: Big) List[Int]:
	return b.items

fn size(xs: List[Int]) Int:
	ys := xs
	return ys.length()

fn both(b: Big) Int:
	n := size(b.items)
	return n + b.name.length()

fn branch(b: Big, flag: Bool) Int:
	if flag: return size(b.items)
	return b.name.length() + b.items.length()

fn reinit(b: Big) Int:
	var c = b
	n := size(c.items)
	c.items = [n, n]
	return c.items.length()

fn nested(w: Wrap) List[Int]:
	return w.inner.items

fn main() Unit:
	name := "a name that is long enough to live on the heap"
	total := (
		items_of(Big(name: name.clone(), items: [1, 2, 3])).length()
		+ both(Big(name: "xy", items: [1, 2]))
		- 2
	)
	(
		stdout().write(
			"{total + branch(Big(name: name.clone(), items: [1]), true)}\n"
		).get()
	)
	(
		stdout()
		.write(
			"{nested(Wrap(inner: Big(name: name.clone(), items: [1, 2, 3]), tag: 1)).length()}\n"
		)
		.get()
	)
	stdout().write("{reinit(Big(name: name.clone(), items: [7]))}\n").get()
