type Counter:
	n: Int

impl Counter:
	var fn bump() Unit:
		self.n = self.n + 1
	fn read() Int:
		return self.n

interface Shape:
	fn area() Int
	var fn grow(by: Int) Unit

fn main() Int:
	return 0
