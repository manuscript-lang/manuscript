// conform: tags=aliasing,records,tier-core
// conform: phase=run
// A field read out of a name bound once leaves the record; the rest of the record is
// released, never the field.
enum Item:
	Null
	Num(n: Int)

type Frame:
	items: List[Item] = []

export fn main() Void:
	var frames: List[Frame] = []
	var items: List[Item] = [Item.Num(5)]
	frames.append(Frame(items: items))
	items = []

	parent := frames.pop() or Frame()
	items = parent.items
	items.append(Item.Num(9))
	print(items.length())

	match items[0]:
		Num(n): print(n)
		_: print("not a number")
