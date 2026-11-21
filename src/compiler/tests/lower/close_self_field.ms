type Source:
	id: Int
	closed: Bool = false

fn move Source.close() Void!:
	if self.closed: return ok()

	self.closed = true
	print(self.id.to_string())

fn main() Int:
	s := Source(id: 1)

	match s.close():
		error(_e): return 1
		ok(_v): return 0
