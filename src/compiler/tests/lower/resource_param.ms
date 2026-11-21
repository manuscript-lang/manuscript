type Latch:
	id: Int

fn Latch.close() Void!:
	return ok()

fn open_latch(id: Int) Latch:
	return Latch(id: id)

fn eat(move l: Latch) Int:
	return l.id

fn main() Int:
	return eat(open_latch(4))
