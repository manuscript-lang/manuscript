interface Reader[A = Int]:
	fn read() A

fn read_all[T: Reader](value: T) Int: return value.read()

type Counter:
	n: Int

fn Counter.read() Int: return self.n

export fn main() Int:
	return read_all(Counter(n: 1))
