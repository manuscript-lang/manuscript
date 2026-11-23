// conform: tags=scope-cleanup,records,tier-core
// conform: phase=run
// A `move` receiver that assigns a field and mutates another still closes the resources
// its fields hold.
import stdout from "@std/io/io.ms"

type Item:
	n: Int

fn move Item.close() Void!:
	void stdout().write(f"closed {self.n}\n")

type Holder:
	items: List[Item]
	last: Item
	tag: Int

fn move Holder.close() Void!:
	while not self.items.is_empty():
		x := self.items.pop()

		if x != null:
			var c = x
			void c.close()

	self.tag = 2

export fn main() Int:
	h := Holder(items: [Item(n: 1), Item(n: 2)], last: Item(n: 3), tag: 1)
	void h.close()
	void stdout().write("done\n")
	return 0
