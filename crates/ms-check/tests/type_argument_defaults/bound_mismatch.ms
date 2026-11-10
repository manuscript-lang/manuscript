interface Reader[A = Int]:
	fn read() A

fn read_all[T: Reader](value: T) Int: return value.read()

type Named:
	name: String

impl Reader[String] for Named:
	fn read() String: return self.name

export fn main() Int:
	return read_all(Named(name: "a"))
