// conform: tags=ownership,records
// conform: phase=check
type Cursor {
	items &List[String]
	at Int
}

fn var Cursor.next() &String? {
	if self.at >= self.items.length() { return null }

	self.at += 1
	return self.items[self.at - 1]
}

fn main() Void {
	var names = ["a", "b"]
	var c = Cursor(names, 0)
	first := c.next()
	second := c.next()
	names.append("z")
	print(first)
	print(second)
}
// expect-error: MS3000 20:5 cannot change `names` while `first` borrows it (binding of a part of it, at 18:5); finish using `first` before this, or give `first` its own value by ending its initializer with `.clone()`
// expect-error: MS3000 20:5 cannot change `names` while `second` borrows it (binding of a part of it, at 19:5); finish using `second` before this, or give `second` its own value by ending its initializer with `.clone()`
