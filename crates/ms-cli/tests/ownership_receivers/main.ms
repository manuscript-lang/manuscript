type Counter:
	n: Int

fn var Counter.bump() Void:
	self.n = self.n + 1
fn Counter.read() Int:
	return self.n

interface Shape:
	fn area() Int
	var fn grow(by: Int) Void

fn main() Int:
	return 0
