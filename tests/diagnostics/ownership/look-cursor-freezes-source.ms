// conform: tags=ownership
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
    names.append("z")
    print(first)
}
// expect-error: MS3000 18:5 cannot change `names` while `first` borrows it (binding of a part of it, at 17:5); finish using `first` before this, or give `first` its own value by ending its initializer with `.clone()`
