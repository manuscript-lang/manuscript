// conform: tags=ownership
// conform: phase=check
import Iterator from "@std/core.ms"

type Counter {
	n Int
}

fn var Counter.next() Int? {
	self.n += 1
	if self.n > 3 { return null }

	return self.n
}

fn total[I Iterator[&Int]](var it I) Int {
	var sum = 0
	for value in it { sum += value }
	return sum
}

fn main() Void {
	print(total(Counter(0)))
}
// expect-error: MS3000 23:11 Counter does not satisfy this bound: it is written with `&`, so the operations must return a `&` result, as `fn var next() &T?` does
