// conform: tags=interfaces,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Item {
	name String
}

interface Sink {
	fn add(move item Item) Int
}

type Shelf {
	items List[Item]
}

type Counter {
	seen Int
}

// Keeps the item: the interface says `move`, so no copy is made.
fn Shelf.add(move item Item) Int {
	var kept = self.items.clone()
	kept.append(item)
	return kept.length()
}

// Only reads the item: `move` still matches, and the item is dropped here.
fn Counter.add(move item Item) Int {
	return item.name.length()
}

fn send(s Sink, move item Item) Int {
	return s.add(item)
}

fn through(f fn(move Item) Int, move item Item) Int {
	return f(item)
}

fn size(move item Item) Int {
	return item.name.length()
}

test "an interface operation declared move takes its argument" {
	expect_equal(send(Shelf([Item("a")]), Item("b")), 2)?
	expect_equal(send(Counter(0), Item("abc")), 3)?
}

test "a function type declared move takes its argument" {
	expect_equal(through(size, Item("ab")), 2)?
	expect_equal(through((move x) => x.name.length() + 1, Item("ab")), 3)?
}
