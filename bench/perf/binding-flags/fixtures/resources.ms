import Closeable from "@std/core.ms"

type Res:
	id: Int
	open: Bool = true

fn var Res.close() Unit!:
	if self.open:
		self.open = false
		print("close {self.id}")

fn borrowed(values: List[Int]) Int:
	a := values
	b := a
	return a.length() + b.length() + values.length()

type Holder:
	items: List[Int]

fn mutate(var holder: Holder) Unit:
	var alias = holder.items
	alias.append(9)

fn conditional(flag: Bool) Unit:
	var value = Res(1)
	if flag:
		value.close().get()

	_after := Res(2)

fn move_through(value: Res) Res:
	return value

fn conditional_move(flag: Bool) Unit:
	value := Res(3)
	if flag:
		_moved := move_through(value)

	_last := Res(4)

fn main() Unit:
	var values = [1, 2]
	count := borrowed(values)
	var holder = Holder(values)
	mutate(var holder)
	print("{count} {holder.items.length()}")
	conditional(true)
	conditional(false)
	conditional_move(true)
	conditional_move(false)
