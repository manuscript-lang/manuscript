type Latch:
	id: Int

fn Latch.close() Void!:
	return ok()

fn open_latch(id: Int) Latch:
	return Latch(id: id)

fn read(l: Latch) Int:
	return l.id

fn twice(id: Int) Int!:
	l := open_latch(id)
	if read(l) > 5:
		return ok(0)
	return ok(read(l) * 2)

fn main() Int:
	r := twice(3)
	return 0
