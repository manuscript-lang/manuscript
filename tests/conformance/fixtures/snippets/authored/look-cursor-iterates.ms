// conform: tags=borrow,look
// conform: phase=run
type Cursor {
    items &List[String]
    at Int
}

fn var Cursor.next() &String? {
    if self.at >= self.items.length() { return null }
    self.at += 1
    return self.items[self.at - 1]
}

fn walk(hold names List[String]) Cursor {
    return Cursor(names, 0)
}

fn main() Void {
    names := ["a", "b", "c"]
    for n in walk(names) {
        print(n)
    }
    print(names.length())
}
