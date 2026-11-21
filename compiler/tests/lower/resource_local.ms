type Door:
	id: Int
	open: Bool

fn Door.close() Void!:
	return ok()

fn make(id: Int) Door:
	return Door(id: id, open: true)

fn peek(d: Door) Int:
	return d.id

fn main() Int:
	d := make(3)
	return peek(d)
