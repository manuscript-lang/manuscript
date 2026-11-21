type Latch:
	id: Int

fn Latch.close() Void!:
	return ok()

fn open_latch(id: Int) Latch:
	return Latch(id: id)

fn eat(move l: Latch) Int:
	return l.id

fn pass(id: Int) Latch:
	l := open_latch(id)
	return l

fn main() Int:
	l := open_latch(4)
	return eat(l)
